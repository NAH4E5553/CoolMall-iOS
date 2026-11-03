import Foundation
import MallCore
@testable import MallData
import Testing

struct ProductReviewsServiceTests {
    static func body(page: Int = 1, total: Int = 12) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "code": 1000,
            "data": [
                "pagination": ["page": page, "size": 10, "total": total],
                "list": [
                    [
                        "id": 1, "goodsId": 830001, "content": "真实映射", "starCount": 4,
                        "nickName": "匿名昵称", "avatarUrl": "https://public.invalid/avatar.png",
                        "createTime": "2026-07-15 21:24:07",
                        "pics": ["https://public.invalid/1.png", "https://public.invalid/2.png"],
                    ]
                ],
            ],
        ])
    }
    @Test func mapsAllReviewFieldsAndServerPaging() throws {
        let page = try ProductReviewsDecoder.page(
            Self.body(), productID: 830001, requestedPage: 1, pageSize: 10)
        #expect(page.nextPage == 2)
        #expect(page.items.map(\.id) == [1])
        #expect(page.items.first?.createdAt == "2026-07-15 21:24:07")
        #expect(page.items.first?.starCount == 4)
        #expect(page.items.first?.nickname == "匿名昵称")
        #expect(page.items.first?.imageURLs.map(\.lastPathComponent) == ["1.png", "2.png"])
        let last = try ProductReviewsDecoder.page(
            Self.body(page: 2), productID: 830001, requestedPage: 2, pageSize: 10)
        #expect(last.nextPage == nil)
        let empty = Data(
            #"{"code":1000,"data":{"list":[],"pagination":{"page":1,"size":10,"total":0}}}"#.utf8)
        #expect(
            try ProductReviewsDecoder.page(empty, productID: 830001, requestedPage: 1, pageSize: 10)
                == ProductReviewPage(items: [], nextPage: nil))
    }
    @Test(arguments: [
        "missing-list", "null-list", "null-pagination", "missing-total", "wrong-page", "wrong-size",
        "negative-total", "wrong-product", "duplicate", "invalid-star", "null-data", "empty-body",
        "oversize",
    ])
    func malformedPageCannotBecomeExhausted(_ mode: String) throws {
        var envelope = try JSONSerialization.jsonObject(with: Self.body()) as! [String: Any]
        var body = envelope["data"] as! [String: Any]
        var meta = body["pagination"] as! [String: Any]
        var rows = body["list"] as! [[String: Any]]
        switch mode {
        case "missing-list": body.removeValue(forKey: "list")
        case "null-list": body["list"] = NSNull()
        case "null-pagination": body["pagination"] = NSNull()
        case "missing-total": meta.removeValue(forKey: "total"); body["pagination"] = meta
        case "wrong-page": meta["page"] = 2; body["pagination"] = meta
        case "wrong-size": meta["size"] = 20; body["pagination"] = meta
        case "negative-total": meta["total"] = -1; body["pagination"] = meta
        case "wrong-product": rows[0]["goodsId"] = 2; body["list"] = rows
        case "duplicate": body["list"] = rows + rows
        case "invalid-star": rows[0]["starCount"] = 6; body["list"] = rows
        case "oversize": body["list"] = Array(repeating: rows[0], count: 11)
        default: break
        }
        envelope["data"] = mode == "null-data" ? NSNull() : body
        let data =
            mode == "empty-body" ? Data() : try JSONSerialization.data(withJSONObject: envelope)
        #expect(throws: ProductDetailLoadFailure.invalidResponse) {
            try ProductReviewsDecoder.page(data, productID: 830001, requestedPage: 1, pageSize: 10)
        }
    }
    actor Transport: ProductDetailTransport {
        var requests: [URLRequest] = []
        let status: Int; let body: Data
        init(status: Int = 200, body: Data) { self.status = status; self.body = body }
        func send(request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            return (
                body,
                HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }
    @Test func exactRequestAndInvalidInputBeforeIO() async throws {
        let transport = Transport(body: try Self.body())
        let service = HTTPProductReviewsService(
            environment: APIEnvironment(baseURL: ProductDetailServiceTests.base),
            transport: transport)
        _ = try await service.loadReviews(productID: 830001, page: 1, pageSize: 10)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://mall.dusksnow.top/app/goods/comment/page")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        let query =
            try JSONSerialization.jsonObject(with: #require(request.httpBody)) as! [String: Any]
        #expect(query["goodsId"] as? String == "830001")
        #expect(query["page"] as? Int == 1); #expect(query["size"] as? Int == 10)
        await #expect(throws: ProductDetailLoadFailure.invalidProductID) {
            try await service.loadReviews(productID: 0, page: 1, pageSize: 10)
        }
        await #expect(throws: ProductDetailLoadFailure.invalidConfiguration) {
            try await service.loadReviews(productID: 1, page: 0, pageSize: 10)
        }
        await #expect(throws: ProductDetailLoadFailure.invalidConfiguration) {
            try await service.loadReviews(productID: 1, page: 1, pageSize: 0)
        }
        #expect(await transport.requests.count == 1)
    }
    @Test func httpAndBusinessFailuresKeepTheirLayer() async {
        let body = Data(#"{"code":1001,"data":null}"#.utf8)
        for status in [503, 200] {
            let service = HTTPProductReviewsService(
                environment: APIEnvironment(baseURL: ProductDetailServiceTests.base),
                transport: Transport(status: status, body: body))
            await #expect(
                throws: status == 503
                    ? ProductDetailLoadFailure.httpStatus(503) : .businessCode(1001)
            ) {
                try await service.loadReviews(productID: 1, page: 1, pageSize: 10)
            }
        }
    }
    struct CancellationTransport: ProductDetailTransport {
        func send(request: URLRequest) async throws -> (Data, URLResponse) {
            throw URLError(.cancelled)
        }
    }
    @Test func cancellationIsNotAnEmptyPageOrNetworkFailure() async {
        let service = HTTPProductReviewsService(
            environment: APIEnvironment(baseURL: ProductDetailServiceTests.base),
            transport: CancellationTransport())
        await #expect(throws: CancellationError.self) {
            try await service.loadReviews(productID: 1, page: 1, pageSize: 10)
        }
    }
}
