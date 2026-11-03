import Foundation
import MallCore
@testable import MallData
import Testing

struct ProductDetailServiceTests {
    static let base = URL(string: "https://mall.dusksnow.top/app/")!
    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json")))
    }

    @Test func capturedDetailUsesIntegerYuanAndOrderedSpecifications() throws {
        let product = try ProductDetailDecoder.detail(
            Self.fixture("product-detail-valid"), productID: 830001)
        #expect(product.id == 830001)
        #expect(product.priceYuan == Decimal(3999))
        #expect(product.sold == 306)
        #expect(product.isAvailable)
        #expect(!product.imageURLs.isEmpty)
        let specs = try ProductDetailDecoder.specifications(
            Self.fixture("product-specifications-valid"), productID: 830001)
        #expect(specs.count == 9)
        #expect(specs.allSatisfy { $0.productID == product.id })
        let raw =
            try JSONSerialization.jsonObject(with: Self.fixture("product-specifications-valid"))
            as! [String: Any]
        let ids = (raw["data"] as! [[String: Any]]).map { ($0["id"] as! NSNumber).int64Value }
        #expect(specs.map(\.id) == ids)
    }

    @Test(arguments: [
        "wrong-id", "missing-title", "blank-title", "negative-price", "negative-sold",
        "unknown-status", "null-goods", "fraction-price", "overflow-id",
    ])
    func invalidDetailIsNotReady(_ mode: String) throws {
        var envelope =
            try JSONSerialization.jsonObject(with: Self.fixture("product-detail-valid"))
            as! [String: Any]
        var body = envelope["data"] as! [String: Any]
        var goods = body["goodsInfo"] as! [String: Any]
        switch mode {
        case "wrong-id": goods["id"] = 2
        case "missing-title": goods.removeValue(forKey: "title")
        case "blank-title": goods["title"] = " \n "
        case "negative-price": goods["price"] = -1
        case "negative-sold": goods["sold"] = -1
        case "unknown-status": goods["status"] = 2
        case "fraction-price": goods["price"] = 1.25
        case "overflow-id": goods["id"] = "9223372036854775808"
        default: break
        }
        body["goodsInfo"] = mode == "null-goods" ? NSNull() : goods
        envelope["data"] = body
        let data = try JSONSerialization.data(withJSONObject: envelope)
        #expect(throws: ProductDetailLoadFailure.invalidResponse) {
            try ProductDetailDecoder.detail(data, productID: 830001)
        }
    }

    @Test func unavailableAndMainImageFallbackAreExplicit() throws {
        var envelope =
            try JSONSerialization.jsonObject(with: Self.fixture("product-detail-valid"))
            as! [String: Any]
        var body = envelope["data"] as! [String: Any]
        var goods = body["goodsInfo"] as! [String: Any]
        goods["status"] = 0;
        goods["pics"] = [" ", "http://unsafe.invalid/a", "https://user:secret@unsafe.invalid/a"]
        goods["mainPic"] = "https://public.invalid/fallback.png"
        goods["subTitle"] = "  "; goods["contentPics"] = []
        body["goodsInfo"] = goods; envelope["data"] = body
        let result = try ProductDetailDecoder.detail(
            JSONSerialization.data(withJSONObject: envelope), productID: 830001)
        #expect(!result.isAvailable)
        #expect(result.imageURLs.map(\.absoluteString) == ["https://public.invalid/fallback.png"])
        #expect(result.subtitle == nil)
        #expect(result.contentImageURLs.isEmpty)
    }

    @Test(arguments: [
        "wrong-product", "duplicate", "negative-stock", "negative-price", "blank-name",
        "invalid-id",
    ])
    func invalidSpecificationsFailWholeResponse(_ mode: String) throws {
        var envelope =
            try JSONSerialization.jsonObject(with: Self.fixture("product-specifications-valid"))
            as! [String: Any]
        var items = envelope["data"] as! [[String: Any]]
        switch mode {
        case "wrong-product": items[0]["goodsId"] = 2
        case "duplicate": items[1]["id"] = items[0]["id"]
        case "negative-stock": items[0]["stock"] = -1
        case "negative-price": items[0]["price"] = -1
        case "blank-name": items[0]["name"] = " "
        default: items[0]["id"] = 0
        }
        envelope["data"] = items
        #expect(throws: ProductDetailLoadFailure.invalidResponse) {
            try ProductDetailDecoder.specifications(
                JSONSerialization.data(withJSONObject: envelope), productID: 830001)
        }
    }

    @Test func emptySpecificationsAndZeroStockAreValid() throws {
        #expect(
            try ProductDetailDecoder.specifications(
                Data(#"{"code":1000,"data":[]}"#.utf8), productID: 830001
            ).isEmpty)
        let data = Data(
            #"{"code":1000,"data":[{"id":1,"goodsId":830001,"name":"无货","price":0,"stock":0,"images":null}]}"#
                .utf8)
        let result = try ProductDetailDecoder.specifications(data, productID: 830001)
        #expect(result.first?.stock == 0)
        #expect(result.first?.priceYuan == 0)
    }

    @Test(arguments: ["empty-body", "null-data", "missing-data", "string-code"])
    func absentOrMalformedPayloadFails(_ scenario: String) {
        // Stable, readable case identity avoids Data's descriptive child nodes
        // being mistaken for separate executions by the existing result parser.
        let data: Data
        switch scenario {
        case "empty-body": data = Data()
        case "null-data": data = Data(#"{"code":1000,"data":null}"#.utf8)
        case "missing-data": data = Data(#"{"code":1000}"#.utf8)
        default: data = Data(#"{"code":"1000","data":{}}"#.utf8)
        }
        #expect(throws: ProductDetailLoadFailure.invalidResponse) {
            try ProductDetailDecoder.detail(data, productID: 830001)
        }
        #expect(throws: ProductDetailLoadFailure.invalidResponse) {
            try ProductDetailDecoder.specifications(data, productID: 830001)
        }
    }

    struct RejectingTransport: ProductDetailTransport {
        let code: URLError.Code
        func send(request: URLRequest) async throws -> (Data, URLResponse) { throw URLError(code) }
    }
    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .cancelled])
    func transportFailuresAndCancellation(_ code: URLError.Code) async {
        let service = HTTPProductDetailService(
            environment: APIEnvironment(baseURL: Self.base),
            transport: RejectingTransport(code: code))
        do {
            _ = try await service.loadDetail(productID: 830001)
            Issue.record("must fail")
        } catch {
            if code == .cancelled {
                #expect(error is CancellationError)
            } else {
                #expect(
                    (error as? ProductDetailLoadFailure)
                        == (code == .timedOut ? .timeout : .networkUnavailable))
            }
        }
    }

    @Test func invalidIDAndConfigurationFailBeforeTransport() async {
        let transport = RejectingTransport(code: .notConnectedToInternet)
        for id: Int64 in [0, -1] {
            let service = HTTPProductDetailService(
                environment: APIEnvironment(baseURL: Self.base), transport: transport)
            await #expect(throws: ProductDetailLoadFailure.invalidProductID) {
                try await service.loadDetail(productID: id)
            }
            await #expect(throws: ProductDetailLoadFailure.invalidProductID) {
                try await service.loadSpecifications(productID: id)
            }
        }
        for base in [
            "http://example.invalid/app/", "https://example.invalid/app",
            "https://user:secret@example.invalid/app/",
        ] {
            let service = HTTPProductDetailService(
                environment: APIEnvironment(baseURL: URL(string: base)!), transport: transport)
            await #expect(throws: ProductDetailLoadFailure.invalidConfiguration) {
                try await service.loadDetail(productID: 1)
            }
        }
    }

    struct ResponseTransport: ProductDetailTransport {
        let status: Int
        let body: Data
        func send(request: URLRequest) async throws -> (Data, URLResponse) {
            (
                body,
                HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }
    @Test func httpFailurePrecedesBusinessAndSchema() async throws {
        let service = HTTPProductDetailService(
            environment: APIEnvironment(baseURL: Self.base),
            transport: ResponseTransport(status: 503, body: Data(#"{"code":1001}"#.utf8)))
        await #expect(throws: ProductDetailLoadFailure.httpStatus(503)) {
            try await service.loadDetail(productID: 1)
        }
        let business = HTTPProductDetailService(
            environment: APIEnvironment(baseURL: Self.base),
            transport: ResponseTransport(
                status: 200, body: Data(#"{"code":1001,"data":null}"#.utf8)))
        await #expect(throws: ProductDetailLoadFailure.businessCode(1001)) {
            try await business.loadDetail(productID: 1)
        }
    }

    /// Echoes the actual URLSession request as required product fields. No
    /// mutable global handler or assumed request-builder output.
    final class EchoProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url else { return }
            let body: Data
            let echo = [
                request.httpMethod ?? "", url.path,
                request.value(forHTTPHeaderField: "Accept") ?? "",
                request.value(forHTTPHeaderField: "Authorization") ?? "none",
                request.value(forHTTPHeaderField: "Cookie") ?? "none",
            ].joined(separator: "|")
            if request.httpMethod == "GET" {
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!
                    .value!
                body = Data(
                    """
                    {"code":1000,"data":{"goodsInfo":{"id":\(id),"title":"\(echo)","price":3999,"sold":0,"status":1}}}
                    """.utf8)
            } else {
                var bytes = request.httpBody
                if bytes == nil, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 1024); var result = Data()
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }; result.append(buffer, count: count)
                    }
                    bytes = result
                }
                let json =
                    (try? JSONSerialization.jsonObject(with: bytes ?? Data()))
                    as? [String: NSNumber]
                let id = json?["goodsId"]?.int64Value ?? -1
                let name = echo + "|" + (request.value(forHTTPHeaderField: "Content-Type") ?? "")
                body = Data(
                    """
                    {"code":1000,"data":[{"id":1,"goodsId":\(id),"name":"\(name)","price":0,"stock":1}]}
                    """.utf8)
            }
            client?.urlProtocol(
                self,
                didReceive: HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @Test func realSessionUsesExactInt64QueryAndPOSTBodyWithoutCredentials() async throws {
        let configuration = URLSessionTransport.makeProductionConfiguration(resourceTimeout: 30)
        configuration.protocolClasses = [EchoProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = HTTPProductDetailService(
            environment: APIEnvironment(baseURL: Self.base),
            transport: URLSessionTransport(session: session))
        let product = try await service.loadDetail(productID: Int64.max)
        #expect(product.id == Int64.max)
        #expect(product.title == "GET|/app/page/goodsDetail|application/json|none|none")
        let specifications = try await service.loadSpecifications(productID: Int64.max)
        #expect(specifications.first?.productID == Int64.max)
        #expect(
            specifications.first?.name
                == "POST|/app/goods/spec/list|application/json|none|none|application/json")
    }
}
