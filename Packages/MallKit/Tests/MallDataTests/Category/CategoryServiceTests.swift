import Foundation
import MallCore
@testable import MallData
import Testing

/// CATEGORY-01 data-path tests over the exact production request/decoding path
/// with a controlled transport: A-GOODS-01 POST identity/empty body, the real
/// captured 43-node payload, field/order edge cases, envelope precedence,
/// cancellation and failure mapping.
struct CategoryServiceTests {
    actor RecordingTransport: CategoryHTTPTransport {
        private var results: [Result<(Data, URLResponse), Error>]
        private(set) var requests: [URLRequest] = []

        init(results: [Result<(Data, URLResponse), Error>] = []) {
            self.results = results
        }

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            guard !results.isEmpty else {
                return (
                    Data(),
                    URLResponse(
                        url: request.url ?? URL(fileURLWithPath: "/stub"), mimeType: nil,
                        expectedContentLength: 0, textEncodingName: nil)
                )
            }
            return try results.removeFirst().get()
        }

        func callCount() -> Int { requests.count }
    }

    static let validURL = URL(string: "https://mall.dusksnow.top/app/")!

    static let capturedData: Data = {
        guard let url = Bundle.module.url(forResource: "category", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            Issue.record("category.json fixture missing from test bundle")
            return Data()
        }
        return data
    }()

    static func http(_ statusCode: Int, url: URL, body: Data) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
            ?? URLResponse(
                url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
    }

    static func ok(_ body: Data) -> Result<(Data, URLResponse), Error> {
        let url = URL(fileURLWithPath: "/stub")
        return .success((body, http(200, url: url, body: body)))
    }

    static func service(_ transport: RecordingTransport) -> HTTPCategoryService {
        HTTPCategoryService(environment: APIEnvironment(baseURL: validURL), transport: transport)
    }

    static func body(_ json: String) -> Data { Data(json.utf8) }

    // MARK: A-GOODS-01 request identity

    @Test func requestIsPostToGoodsTypeListWithEmptyBodyAndNoCredentials() async throws {
        let transport = RecordingTransport(results: [Self.ok(Self.capturedData)])
        _ = try await Self.service(transport).loadCategories()
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://mall.dusksnow.top/app/goods/type/list")
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody?.isEmpty == true)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.query == nil)
    }

    // MARK: captured production payload

    @Test func capturedFlatResponseMapsAllFieldsAndKeepsPayloadOrder() async throws {
        let categories = try await Self.service(
            RecordingTransport(results: [Self.ok(Self.capturedData)])
        ).loadCategories()

        #expect(categories.count == 43)
        #expect(categories.filter { $0.parentID == nil }.count == 10)
        #expect(categories.filter { $0.parentID != nil }.count == 33)
        // The payload is NOT pre-sorted: the data layer preserves response order
        // and the page projection owns sortNum ordering.
        #expect(categories.first?.id == 800_010)
        #expect(categories.first?.sortNum == 10)

        let xiaomi = try #require(categories.first { $0.id == 801_001 })
        #expect(xiaomi.name == "Xiaomi 数字旗舰")
        #expect(xiaomi.parentID == 800_001)
        #expect(xiaomi.sortNum == 1)
        #expect(xiaomi.imageURL?.scheme == "https")
        #expect(xiaomi.imageURL?.host == "cdn.cnbj1.fds.api.mi-img.com")

        #expect(Set(categories.map(\.id)).count == categories.count)
    }

    @Test func unknownFieldsAreIgnoredAndStatusTimestampsAreNotConsumed() async throws {
        let json = """
            {"code":1000,"data":[{"id":1,"name":"节点","parentId":null,"sortNum":1,
            "pic":null,"status":0,"createTime":"x","updateTime":"y","unknown":[1,2]}]}
            """
        let categories = try await Self.service(
            RecordingTransport(results: [Self.ok(Self.body(json))])
        ).loadCategories()
        #expect(categories.count == 1)
        #expect(categories.first?.sortNum == 1)
        #expect(categories.first?.imageURL == nil)
    }

    @Test func missingAndNullSortNumKeepReferenceZeroDefault() async throws {
        let json = """
            {"code":1000,"data":[
            {"id":1,"name":"缺排序","parentId":null},
            {"id":2,"name":"空排序","parentId":null,"sortNum":null},
            {"id":3,"name":"正常","parentId":null,"sortNum":7}
            ]}
            """
        let categories = try await Self.service(
            RecordingTransport(results: [Self.ok(Self.body(json))])
        ).loadCategories()
        #expect(categories.map(\.sortNum) == [0, 0, 7])
    }

    @Test func emptyArrayIsSuccessfulEmptyAndNullOrMissingDataIsPayloadFailure() async throws {
        let empty = try await Self.service(
            RecordingTransport(results: [Self.ok(Self.body(#"{"code":1000,"data":[]}"#))])
        ).loadCategories()
        #expect(empty.isEmpty)

        let invalidBodies = [
            #"{"code":1000}"#,
            #"{"code":1000,"data":null}"#,
            #"{"code":1000,"data":{}}"#,
            #"{"code":1000,"data":"x"}"#,
        ]
        for body in invalidBodies {
            await #expect(throws: CategoryLoadFailure.invalidPayload) {
                _ = try await Self.service(
                    RecordingTransport(results: [Self.ok(Self.body(body))])
                ).loadCategories()
            }
        }
    }

    // MARK: field contract

    @Test func requiredFieldViolationsFailWholeRead() async throws {
        let cases = [
            #"{"code":1000,"data":[{"id":0,"name":"零","parentId":null}]}"#,
            #"{"code":1000,"data":[{"id":-3,"name":"负","parentId":null}]}"#,
            #"{"code":1000,"data":[{"name":"缺ID","parentId":null}]}"#,
            #"{"code":1000,"data":[{"id":1,"name":" ","parentId":null}]}"#,
            #"{"code":1000,"data":[{"id":1,"parentId":null}]}"#,
            #"{"code":1000,"data":[{"id":1,"name":"重复","parentId":null},{"id":1,"name":"重复2","parentId":null}]}"#,
            #"{"code":1000,"data":[{"id":"1","name":"字符串ID","parentId":null}]}"#,
            #"{"code":1000,"data":[{"id":1,"name":9,"parentId":null}]}"#,
            #"{"code":1000,"data":[{"id":1,"name":"父类型","parentId":"800001"}]}"#,
            #"{"code":1000,"data":[{"id":1,"name":"排序类型","sortNum":true}]}"#,
            #"{"code":1000,"data":[{"id":1,"name":"图类型","pic":123}]}"#,
            #"{"code":1000,"data":[{"id":9223372036854775808,"name":"ID溢出"}]}"#,
        ]
        for body in cases {
            await #expect(throws: CategoryLoadFailure.invalidPayload) {
                _ = try await Self.service(
                    RecordingTransport(results: [Self.ok(Self.body(body))])
                ).loadCategories()
            }
        }
    }

    @Test func imageTextRulesMatchTheImageContract() async throws {
        let good = "https://cdn.example.com/cat.png"
        let json = """
            {"code":1000,"data":[
            {"id":1,"name":"缺图","parentId":null},
            {"id":2,"name":"空图","parentId":null,"pic":""},
            {"id":3,"name":"相对","parentId":null,"pic":"/cat.png"},
            {"id":4,"name":"http","parentId":null,"pic":"http://cdn.example.com/cat.png"},
            {"id":5,"name":"乱文本","parentId":null,"pic":"not a url"},
            {"id":6,"name":"好图","parentId":null,"pic":"\(good)"}
            ]}
            """
        let categories = try await Self.service(
            RecordingTransport(results: [Self.ok(Self.body(json))])
        ).loadCategories()
        #expect(categories[0].imageURL == nil)
        #expect(categories[1].imageURL == nil)
        #expect(categories[2].imageURL == nil)
        #expect(categories[3].imageURL == nil)
        #expect(categories[4].imageURL == nil)
        #expect(categories[5].imageURL?.absoluteString == good)
    }

    // MARK: envelope / transport precedence

    @Test func envelopeShapeFailuresAreInvalidResponse() async throws {
        let cases = [
            #"{"code":null,"data":[]}"#,
            #"{"data":[]}"#,
            #"{"code":true,"data":[]}"#,
            #"{"code":"1000","data":[]}"#,
            "not json at all",
            "[]",
        ]
        for body in cases {
            await #expect(throws: CategoryLoadFailure.invalidResponse) {
                _ = try await Self.service(
                    RecordingTransport(results: [Self.ok(Self.body(body))])
                ).loadCategories()
            }
        }
    }

    @Test func httpAndBusinessFailuresTakePrecedenceWithoutBodyParsing() async throws {
        let stubURL = URL(fileURLWithPath: "/stub")
        let responses: [(Result<(Data, URLResponse), Error>, CategoryLoadFailure)] = [
            (
                .success((Data("garbage".utf8), Self.http(503, url: stubURL, body: Data()))),
                .httpStatus(503)
            ),
            (
                Self.ok(Self.body(#"{"code":9001,"data":{"unexpected":true}}"#)),
                .businessCode(9001)
            ),
            (Self.ok(Data()), .invalidResponse),
        ]
        for (response, expected) in responses {
            await #expect(throws: expected) {
                _ = try await Self.service(RecordingTransport(results: [response]))
                    .loadCategories()
            }
        }
    }

    @Test func nonHTTPResponseFailsInvalidResponse() async throws {
        let transport = RecordingTransport(results: [
            .success(
                (
                    Data(),
                    URLResponse(
                        url: Self.validURL, mimeType: nil, expectedContentLength: 0,
                        textEncodingName: nil)
                ))
        ])
        await #expect(throws: CategoryLoadFailure.invalidResponse) {
            _ = try await Self.service(transport).loadCategories()
        }
    }

    @Test func transportErrorsMapToTimeoutNetworkAndCancellation() async throws {
        await #expect(throws: CategoryLoadFailure.timeout) {
            _ = try await Self.service(
                RecordingTransport(results: [.failure(URLError(.timedOut))])
            ).loadCategories()
        }
        await #expect(throws: CategoryLoadFailure.networkUnavailable) {
            _ = try await Self.service(
                RecordingTransport(results: [.failure(URLError(.cannotConnectToHost))])
            ).loadCategories()
        }
        await #expect(throws: CancellationError.self) {
            _ = try await Self.service(
                RecordingTransport(results: [.failure(URLError(.cancelled))])
            ).loadCategories()
        }
    }

    @Test func invalidConfigurationFailsBeforeAnyRequest() async throws {
        let badBases = [
            URL(string: "http://mall.dusksnow.top/app/")!,
            URL(string: "https://mall.dusksnow.top/app")!,
        ]
        for base in badBases {
            let transport = RecordingTransport()
            let service = HTTPCategoryService(
                environment: APIEnvironment(baseURL: base), transport: transport)
            await #expect(throws: CategoryLoadFailure.invalidConfiguration) {
                _ = try await service.loadCategories()
            }
            let calls = await transport.callCount()
            #expect(calls == 0)
        }

        for environment in [
            APIEnvironment(baseURL: Self.validURL, requestTimeout: 0),
            APIEnvironment(baseURL: Self.validURL, resourceTimeout: -1),
        ] {
            let transport = RecordingTransport()
            let service = HTTPCategoryService(environment: environment, transport: transport)
            await #expect(throws: CategoryLoadFailure.invalidConfiguration) {
                _ = try await service.loadCategories()
            }
            let calls = await transport.callCount()
            #expect(calls == 0)
        }
    }
}
