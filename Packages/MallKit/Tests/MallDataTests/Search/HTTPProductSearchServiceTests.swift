import Foundation
import MallCore
import Testing
@testable import MallData

struct HTTPProductSearchServiceTests {
    @Test func categoryOnlyAndExplicitAllProductsEncodeRealPagingWithoutKeyword() async throws {
        let transport = SearchTransport(); let service = service(transport)
        _ = try await service.search(
            .init(keyword: "", categoryIDs: [801008]), page: 1, pageSize: 10)
        _ = try await service.search(.init(keyword: "", allProducts: true), page: 1, pageSize: 10)
        let requests = await transport.requests
        let bodies = try requests.map { request in
            let requestBody = try #require(request.httpBody)
            return try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        }
        #expect(bodies[0]["typeId"] as? [Int] == [801008])
        #expect(bodies[1]["typeId"] == nil)
        #expect(
            bodies.allSatisfy {
                $0["keyWord"] == nil && $0["featured"] == nil && $0["allProducts"] == nil
            })
        #expect(SearchQuery(keyword: "", categoryIDs: [801008]).isValid)
        #expect(!SearchQuery(keyword: "", categoryIDs: [0]).isValid)
        #expect(!SearchQuery(keyword: "", categoryIDs: [-1]).isValid)
        #expect(!SearchQuery(keyword: "").isValid)
    }
    private func service(_ transport: SearchTransport) -> HTTPProductSearchService {
        guard let url = URL(string: "https://search.invalid/app/") else {
            preconditionFailure("fixture URL")
        }
        return HTTPProductSearchService(
            environment: APIEnvironment(baseURL: url),
            transport: transport)
    }
    @Test func exactKeywordFiltersMoneyOrderPagingWithoutAuthorization() async throws {
        let transport = SearchTransport(); let service = service(transport)
        let query = SearchQuery(
            keyword: " 小米 手机 ", categoryIDs: [3, 2, 3],
            minimumPrice: Decimal(string: "299.15"), maximumPrice: 999, sort: .salesDescending)
        let page = try await service.search(query, page: 1, pageSize: 10)
        #expect(page.items.first?.priceYuan == Decimal(string: "3999.25"))
        #expect(page.items.first?.sold == nil)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://search.invalid/app/goods/info/page")
        #expect(request.httpMethod == "POST");
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let requestBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(body["featured"] == nil && body["recommend"] == nil)
        #expect(body["keyWord"] as? String == "小米 手机"); #expect(body["keyword"] == nil)
        #expect(body["typeId"] as? [Int] == [2, 3]);
        #expect(body["minPrice"] as? String == "299.15")
        #expect(body["maxPrice"] as? String == "999"); #expect(body["order"] as? String == "sold")
        #expect(body["sort"] as? String == "desc"); #expect(body["size"] as? Int == 10)
    }
    @Test func comprehensiveOmitsUnsetFiltersAndDirectionsUseBackendFields() async throws {
        let transport = SearchTransport(); let service = service(transport)
        for sort in [SearchSort.comprehensive, .salesAscending, .priceAscending, .priceDescending] {
            _ = try await service.search(.init(keyword: "x", sort: sort), page: 1, pageSize: 10)
        }
        let requests = await transport.requests
        let bodies = try requests.map { request in
            let requestBody = try #require(request.httpBody)
            return try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        }
        #expect(bodies[0]["order"] == nil && bodies[0]["sort"] == nil)
        #expect(
            bodies[0]["typeId"] == nil && bodies[0]["minPrice"] == nil
                && bodies[0]["maxPrice"] == nil)
        #expect(bodies[1]["order"] as? String == "sold" && bodies[1]["sort"] as? String == "asc")
        #expect(bodies[2]["order"] as? String == "price" && bodies[2]["sort"] as? String == "asc")
        #expect(bodies[3]["sort"] as? String == "desc")
    }
    @Test func featuredCollectionOmitsEmptyKeywordAndPreservesFlagOnFilteredPages() async throws {
        let transport = SearchTransport(); let service = service(transport)
        _ = try await service.search(.init(keyword: "", featuredOnly: true), page: 1, pageSize: 10)
        _ = try await service.search(
            .init(
                keyword: " 手机 ", categoryIDs: [2], minimumPrice: 10, maximumPrice: 999,
                sort: .priceDescending, featuredOnly: true), page: 1, pageSize: 10)
        let requests = await transport.requests
        let bodies = try requests.map { request in
            let body = try #require(request.httpBody)
            return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
        #expect(bodies.allSatisfy { $0["featured"] as? Bool == true && $0["recommend"] == nil })
        #expect(bodies[0]["keyWord"] == nil)
        #expect(bodies[1]["keyWord"] as? String == "手机")
        #expect(bodies[1]["typeId"] as? [Int] == [2])
        #expect(bodies[1]["minPrice"] as? String == "10")
        #expect(bodies[1]["maxPrice"] as? String == "999")
        #expect(bodies[1]["order"] as? String == "price" && bodies[1]["sort"] as? String == "desc")
        #expect(SearchQuery(keyword: "", featuredOnly: true) != SearchQuery(keyword: ""))
    }
    @Test func keywordsHaveNoBodyKeepOrderTrimAndDeduplicate() async throws {
        let transport = SearchTransport(
            response:
                "{\"code\":1000,\"data\":[{\"name\":\" b \"},{\"name\":\"a\"},{\"name\":\"b\"},{\"name\":\" \"}]}"
        )
        #expect(try await service(transport).loadSearchKeywords() == ["b", "a"])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/app/goods/search/keyword/list");
        #expect(request.httpBody == nil)
    }
    @Test func businessHttpMissingPayloadAndMalformedPageAreFailuresNotEmpty() async throws {
        let failures = [
            "{\"code\":500,\"message\":\"拒绝\"}", "{\"code\":1000,\"data\":null}", "{}",
            "{\"code\":1000,\"data\":{\"list\":[],\"pagination\":{\"page\":2,\"size\":10,\"total\":0}}}",
        ]
        for response in failures {
            await #expect(throws: PageReadFailure.self) {
                _ = try await service(SearchTransport(response: response)).search(
                    .init(keyword: "x"), page: 1, pageSize: 10)
            }
        }
        await #expect(throws: PageReadFailure.authenticationRequired) {
            _ = try await service(SearchTransport(status: 401)).search(
                .init(keyword: "x"), page: 1, pageSize: 10)
        }
    }
    @Test func invalidProductsAndDuplicateIdentityAreNotDisplayed() async throws {
        for row in [
            #"{"id":0,"title":"手机","price":10}"#,
            #"{"id":1,"title":" ","price":10}"#,
            #"{"id":1,"title":"手机","price":-1}"#,
            #"{"id":1,"title":"手机","price":10,"sold":-1}"#,
        ] {
            let response =
                #"{"code":1000,"data":{"list":["# + row
                + #"],"pagination":{"page":1,"size":10,"total":1}}}"#
            await #expect(throws: PageReadFailure.invalidResponse) {
                _ = try await service(SearchTransport(response: response)).search(
                    .init(keyword: "x"), page: 1, pageSize: 10)
            }
        }
        let row = #"{"id":1,"title":"手机","price":10}"#
        let response =
            #"{"code":1000,"data":{"list":["# + row + "," + row
            + #"],"pagination":{"page":1,"size":10,"total":2}}}"#
        await #expect(throws: PageReadFailure.invalidResponse) {
            _ = try await service(SearchTransport(response: response)).search(
                .init(keyword: "x"), page: 1, pageSize: 10)
        }
    }
    @Test func invalidQueryNeverMakesRequestAndValidEmptyIsEmpty() async throws {
        let transport = SearchTransport(); let service = service(transport)
        for query in [
            SearchQuery(keyword: " "), .init(keyword: "x", minimumPrice: -1),
            .init(keyword: "x", minimumPrice: 2, maximumPrice: 1),
            .init(keyword: "x", categoryIDs: [0]),
        ] {
            await #expect(throws: PageReadFailure.invalidConfiguration) {
                _ = try await service.search(query, page: 1, pageSize: 10)
            }
        }
        #expect(await transport.requests.isEmpty)
        let empty = SearchTransport(
            response:
                "{\"code\":1000,\"data\":{\"list\":[],\"pagination\":{\"page\":1,\"size\":10,\"total\":0}}}"
        )
        #expect(
            try await self.service(empty).search(.init(keyword: "x"), page: 1, pageSize: 10).items
                .isEmpty)
    }
}
private actor SearchTransport: ProductDetailTransport {
    var requests: [URLRequest] = []
    let response: String
    let status: Int
    init(
        response: String =
            "{\"code\":1000,\"data\":{\"list\":[{\"id\":1,\"title\":\"手机\",\"price\":3999.25}],\"pagination\":{\"page\":1,\"size\":10,\"total\":1}}}",
        status: Int = 200
    ) { self.response = response; self.status = status }
    func send(request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let url = try #require(request.url)
        let response = try #require(
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(self.response.utf8), response)
    }
}
