import Foundation
import MallCore
@testable import MallData
import Testing

/// H0 service-level tests over the exact production request/decoding path
/// with a controlled transport (AT-HOME-01-01…05, plus only-categoryAll and
/// configuration failures). The benchmark input is the frozen H0-VALID pure
/// envelope; error variants are constructed in-test.
struct HomeServiceTests {
    actor StubTransport: HTTPTransport {
        private var responses: [Result<(Data, URLResponse), Error>]

        init(responses: [Result<(Data, URLResponse), Error>] = []) {
            self.responses = responses
        }

        func send(url: URL, timeout: TimeInterval) async throws -> (Data, URLResponse) {
            guard let response = responses.first else {
                return (
                    Data(),
                    URLResponse(
                        url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
                )
            }
            responses.removeFirst()
            return try response.get()
        }
    }

    static let validData: Data = {
        let url = Bundle.module.url(forResource: "home-valid", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else {
            Issue.record("home-valid.json fixture missing from test bundle")
            return Data()
        }
        return data
    }()

    static func http(_ statusCode: Int, url: URL, body: Data) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
            ?? URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
    }

    static func ok(_ body: Data) -> Result<(Data, URLResponse), Error> {
        let url = URL(fileURLWithPath: "/stub")
        return .success((body, http(200, url: url, body: body)))
    }

    static let validURL = URL(string: "https://mall.dusksnow.top/app/")!

    static func service(_ transport: StubTransport) -> HTTPHomeService {
        HTTPHomeService(environment: APIEnvironment(baseURL: validURL), transport: transport)
    }

    // MARK: AT-01 valid envelope, order and exact values

    @Test func validEnvelopeMapsSevenSectionsInOrderWithExactPrices() async throws {
        let transport = StubTransport(responses: [Self.ok(Self.validData)])
        let snapshot = try await Self.service(transport).loadHome()

        #expect(snapshot.banners.count == 6)
        #expect(snapshot.coupons.count == 3)
        #expect(snapshot.categories.count == 10)
        #expect(snapshot.allCategories.count == 43)
        #expect(snapshot.featured.count == 8)
        #expect(snapshot.recommendations.count == 8)
        #expect(snapshot.goods.count == 10)

        // 830001/3999 lives in flashSale[0]; goods[0] is 1/5499; recommend[0]
        // is 830009/4999 — sections are never mixed.
        #expect(snapshot.featured.first?.id == 830_001)
        #expect(snapshot.featured.first?.priceYuan == Decimal(3999))
        #expect(snapshot.goods.first?.id == 1)
        #expect(snapshot.goods.first?.priceYuan == Decimal(5499))
        #expect(snapshot.recommendations.first?.id == 830_009)
        #expect(snapshot.recommendations.first?.priceYuan == Decimal(4999))

        #expect(snapshot.banners.first?.id == 810_001)
        #expect(snapshot.categories.first?.id == 800_001)
        #expect(snapshot.coupons.first?.id == 860_001)
        // Real CDN URLs from the sample are kept as absolute HTTPS.
        #expect(snapshot.banners.first?.imageURL?.scheme == "https")
    }

    @Test func invalidConfigurationFailsBeforeAnyRequest() async {
        let transport = StubTransport()
        let badBase = URL(string: "http://mall.dusksnow.top/app/")!  // not HTTPS
        let service = HTTPHomeService(
            environment: APIEnvironment(baseURL: badBase), transport: transport
        )
        await #expect(throws: HomeLoadFailure.invalidConfiguration) {
            _ = try await service.loadHome()
        }
    }

    @Test func trailingSlashMissingBaseFailsConfiguration() async {
        let service = HTTPHomeService(
            environment: APIEnvironment(
                baseURL: URL(string: "https://mall.dusksnow.top/app")!
            ),
            transport: StubTransport()
        )
        await #expect(throws: HomeLoadFailure.invalidConfiguration) {
            _ = try await service.loadHome()
        }
    }

    @Test func nonPositiveTimeoutFailsConfiguration() async {
        let service = HTTPHomeService(
            environment: APIEnvironment(
                baseURL: Self.validURL, requestTimeout: 0
            ),
            transport: StubTransport()
        )
        await #expect(throws: HomeLoadFailure.invalidConfiguration) {
            _ = try await service.loadHome()
        }
    }

    // MARK: AT-02 valid empty shapes

    @Test func allSevenMissingOrNullAndEmptyArraysAreValidEmpty() async throws {
        let bodies = [
            #"{"code":1000,"data":{}}"#,
            #"{"code":1000,"data":{"banner":null,"category":null,"categoryAll":null,"flashSale":null,"recommend":null,"goods":null,"coupon":null}}"#,
            #"{"code":1000,"data":{"banner":[],"category":[],"categoryAll":[],"flashSale":[],"recommend":[],"goods":[],"coupon":[]}}"#,
        ]
        for body in bodies {
            let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
            let snapshot = try await Self.service(transport).loadHome()
            #expect(snapshot.banners.isEmpty && snapshot.coupons.isEmpty)
            #expect(snapshot.categories.isEmpty && snapshot.allCategories.isEmpty)
            #expect(snapshot.featured.isEmpty && snapshot.recommendations.isEmpty)
            #expect(snapshot.goods.isEmpty)
        }
    }

    @Test func onlyCategoryAllNonEmptyIsStillEmptyButKeepsAuxiliary() async throws {
        let body =
            #"{"code":1000,"data":{"categoryAll":[{"id":800001,"name":"手机","parentId":null}]}}"#
        let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
        let snapshot = try await Self.service(transport).loadHome()
        #expect(snapshot.banners.isEmpty && snapshot.goods.isEmpty)
        #expect(snapshot.allCategories.count == 1)
        #expect(snapshot.allCategories.first?.name == "手机")
    }

    @Test func sectionPresentButNotArrayFailsNotEmpty() async {
        let body = #"{"code":1000,"data":{"goods":"oops"}}"#
        let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
        await #expect(throws: HomeLoadFailure.invalidPayload) {
            _ = try await Self.service(transport).loadHome()
        }
    }

    @Test func envelopeShapeFailuresAreInvalidResponseOrPayload() async {
        let cases: [(String, HomeLoadFailure)] = [
            (#"{"code":null,"data":{}}"#, .invalidResponse),
            (#"{"data":{}}"#, .invalidResponse),
            (#"{"code":true,"data":{}}"#, .invalidResponse),
            (#"{"code":"1000","data":{}}"#, .invalidResponse),
            (#"not json at all"#, .invalidResponse),
            ("[]", .invalidResponse),
            (#"{"code":1000}"#, .invalidPayload),  // data missing
            (#"{"code":1000,"data":null}"#, .invalidPayload),
            (#"{"code":1000,"data":5}"#, .invalidPayload),
            (#"{"code":1000,"data":"x"}"#, .invalidPayload),
        ]
        for (body, expected) in cases {
            let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
            await #expect(throws: expected) {
                _ = try await Self.service(transport).loadHome()
            }
        }
    }

    // MARK: AT-03 HTTP/business precedence

    @Test func httpFailureWinsEvenWithBadBodyAndBusinessCodeWinsOverBadData() async {
        let stubURL = URL(fileURLWithPath: "/stub")
        let cases: [(Result<(Data, URLResponse), Error>, HomeLoadFailure)] = [
            // HTTP 503 with a garbage body: HTTP layer first.
            (
                .success((Data("garbage".utf8), Self.http(503, url: stubURL, body: Data()))),
                .httpStatus(503)
            ),
            // Business 9001 with an error payload: business code, no data parsing.
            (
                Self.ok(Data(#"{"code":9001,"data":{"unexpected":true}}"#.utf8)),
                .businessCode(9001)
            ),
            // Empty body with HTTP 200: header decode impossible.
            (Self.ok(Data()), .invalidResponse),
        ]
        for (response, expected) in cases {
            let transport = StubTransport(responses: [response])
            await #expect(throws: expected) {
                _ = try await Self.service(transport).loadHome()
            }
        }
    }

    @Test func nonHTTPResponseFailsInvalidResponse() async {
        let url = URL(string: "https://mall.dusksnow.top/app/page/home")!
        let transport = StubTransport(
            responses: [
                .success(
                    (
                        Data(),
                        URLResponse(
                            url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil
                        )
                    ))
            ]
        )
        await #expect(throws: HomeLoadFailure.invalidResponse) {
            _ = try await Self.service(transport).loadHome()
        }
    }

    // MARK: AT-04 field contract

    @Test func idAndPriceViolationsFailWholeRead() async {
        let cases: [String] = [
            #"{"code":1000,"data":{"goods":[{"id":0,"title":"零","price":1}]}}"#,
            #"{"code":1000,"data":{"goods":[{"id":-3,"title":"负","price":1}]}}"#,
            #"{"code":1000,"data":{"goods":[{"title":"缺ID","price":1}]}}"#,
            #"{"code":1000,"data":{"goods":[{"id":1,"title":"a","price":1},{"id":1,"title":"b","price":2}]}}"#,
            #"{"code":1000,"data":{"goods":[{"id":1,"title":"  ","price":1}]}}"#,
            #"{"code":1000,"data":{"goods":[{"id":1,"title":"缺价"}]}}"#,
            #"{"code":1000,"data":{"goods":[{"id":1,"title":"负价","price":-1}]}}"#,
            #"{"code":1000,"data":{"goods":[{"id":1,"title":"小数价","price":1.5}]}}"#,
            #"{"code":1000,"data":{"goods":[{"id":1,"title":"字符串价","price":"9"}]}}"#,
            #"{"code":1000,"data":{"coupon":[{"id":860001,"title":"  "}]}}"#,
            #"{"code":1000,"data":{"category":[{"id":800001,"name":" "}]}}"#,
            #"{"code":1000,"data":{"category":[{"id":800001,"name":"x","parentId":"nope"}]}}"#,
        ]
        for body in cases {
            let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
            await #expect(throws: HomeLoadFailure.invalidPayload) {
                _ = try await Self.service(transport).loadHome()
            }
        }
    }

    @Test func crossSectionSameGoodsIDIsAllowed() async throws {
        let shared = #"{"id":830001,"title":"同款","subTitle":null,"mainPic":null,"price":100}"#
        let body =
            #"{"code":1000,"data":{"flashSale":[\#(shared)],"recommend":[\#(shared)],"goods":[\#(shared)]}}"#
        let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
        let snapshot = try await Self.service(transport).loadHome()
        #expect(snapshot.featured.first?.id == 830_001)
        #expect(snapshot.recommendations.first?.id == 830_001)
        #expect(snapshot.goods.first?.id == 830_001)
    }

    @Test func unknownFieldsAreIgnored() async throws {
        let body = """
            {"code":1000,"data":{"coupon":[{"id":860001,"title":"券","condition":"满299","type":9,
            "startTime":"2026-01-01","unknownObject":{"a":1}}],"goods":[{"id":1,"title":"商品",
            "typeId":801001,"status":1,"createTime":"x","price":10}]}}
            """
        let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
        let snapshot = try await Self.service(transport).loadHome()
        #expect(snapshot.coupons.count == 1)
        #expect(snapshot.goods.first?.priceYuan == Decimal(10))
    }

    // MARK: AT-05 optional text and image URL rules

    @Test func imageURLTextRulesMapToNilButKeepOthers() async throws {
        let good = "https://cdn.example.com/x.jpg"
        let body = """
            {"code":1000,"data":{"banner":[
            {"id":1,"description":"无图","pic":null},
            {"id":2,"description":"空串","pic":""},
            {"id":3,"description":"相对路径","pic":"/nr/a.jpg"},
            {"id":4,"description":"http","pic":"http://cdn.example.com/a.jpg"},
            {"id":5,"description":"乱文本","pic":"not a url"},
            {"id":6,"description":"好图","pic":"\(good)"},
            {"id":7,"description":"缺pic"},
            {"id":8,"pic":"\(good)"}
            ]}}
            """
        let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
        let snapshot = try await Self.service(transport).loadHome()
        let urls = snapshot.banners.map(\.imageURL)
        #expect(urls[0] == nil && urls[1] == nil && urls[2] == nil)
        #expect(urls[3] == nil && urls[4] == nil)
        #expect(urls[5]?.absoluteString == good)
        #expect(urls[6] == nil)
        #expect(snapshot.banners[0].description == "无图")
        #expect(snapshot.banners[7].description == "")
    }

    @Test func nonStringImageValueFails() async {
        let body = #"{"code":1000,"data":{"banner":[{"id":1,"description":"d","pic":123}]}}"#
        let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
        await #expect(throws: HomeLoadFailure.invalidPayload) {
            _ = try await Self.service(transport).loadHome()
        }
    }

    @Test func subTitleOptionalStringRules() async throws {
        let body = """
            {"code":1000,"data":{"goods":[
            {"id":1,"title":"无副标题","price":1},
            {"id":2,"title":"null副标题","subTitle":null,"price":1},
            {"id":3,"title":"有副标题","subTitle":"旗舰","price":1}
            ]}}
            """
        let transport = StubTransport(responses: [Self.ok(Data(body.utf8))])
        let snapshot = try await Self.service(transport).loadHome()
        #expect(snapshot.goods[0].subtitle == nil)
        #expect(snapshot.goods[1].subtitle == nil)
        #expect(snapshot.goods[2].subtitle == "旗舰")
    }

    @Test func fixtureServiceMapsBundledValidEnvelope() async throws {
        // FixtureHomeService shares the exact envelope/mapping path (H0).
        let snapshot = try await FixtureHomeService().loadHome()
        #expect(snapshot.banners.count == 6)
        #expect(snapshot.allCategories.count == 43)
        #expect(snapshot.featured.first?.id == 830_001)
        #expect(snapshot.goods.first?.id == 1)
    }
}
