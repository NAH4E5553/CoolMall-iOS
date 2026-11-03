import Foundation
import MallCore

/// Public catalogue reads only. No credential, automatic retry, local sorting or filtered-page cache.
public final class HTTPProductSearchService: ProductSearchLoading, SearchKeywordsLoading, Sendable {
    private let environment: APIEnvironment
    private let transport: any ProductDetailTransport
    public convenience init(environment: APIEnvironment) {
        self.init(
            environment: environment,
            transport: URLSessionTransport(resourceTimeout: environment.resourceTimeout))
    }
    init(environment: APIEnvironment, transport: any ProductDetailTransport) {
        self.environment = environment; self.transport = transport
    }
    public func loadSearchKeywords() async throws -> [String] {
        let request = try CouponHTTP.request(environment, path: "goods/search/keyword/list")
        let data = try await CouponHTTP.body(request, transport: transport)
        guard let header = try? JSONDecoder().decode(EnvelopeHeader.self, from: data) else {
            throw PageReadFailure.invalidResponse
        }
        guard header.code == 1000 else { throw PageReadFailure.businessCode(header.code) }
        struct Keyword: Decodable { let name: String }
        guard let words = try? JSONDecoder().decode(Envelope<[Keyword]>.self, from: data).data
        else {
            throw PageReadFailure.invalidResponse
        }
        var seen = Set<String>()
        return words.compactMap {
            let value = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && seen.insert(value).inserted ? value : nil
        }
    }
    public func search(_ query: SearchQuery, page: Int, pageSize: Int) async throws
        -> NumberedPage<SearchProductSummary>
    {
        guard query.isValid else { throw PageReadFailure.invalidConfiguration }
        struct Body: Encodable {
            let page: Int; let size: Int; let keyWord: String?; let featured: Bool?;
            let typeId: [Int64]?
            let minPrice: String?; let maxPrice: String?; let order: String?; let sort: String?
        }
        let order: String?; let sort: String?
        switch query.sort {
        case .comprehensive: order = nil; sort = nil
        case .salesAscending: order = "sold"; sort = "asc"
        case .salesDescending: order = "sold"; sort = "desc"
        case .priceAscending: order = "price"; sort = "asc"
        case .priceDescending: order = "price"; sort = "desc"
        }
        var request = try CouponHTTP.request(
            environment, path: "goods/info/page", page: page, size: pageSize)
        request.httpBody = try JSONEncoder().encode(
            Body(
                page: page, size: pageSize, keyWord: query.keyword.isEmpty ? nil : query.keyword,
                featured: query.featuredOnly ? true : nil,
                typeId: query.categoryIDs.isEmpty ? nil : query.categoryIDs,
                minPrice: query.minimumPrice.map { NSDecimalNumber(decimal: $0).stringValue },
                maxPrice: query.maximumPrice.map { NSDecimalNumber(decimal: $0).stringValue },
                order: order, sort: sort))
        let data = try await CouponHTTP.body(request, transport: transport)
        return try CouponPageDecoder.page(data, requestedPage: page, size: pageSize) {
            (dto: ProductDTO) in
            guard dto.id > 0, !dto.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !dto.price.isNaN, dto.price >= 0, dto.sold.map({ $0 >= 0 }) ?? true
            else {
                throw PageReadFailure.invalidResponse
            }
            let url = dto.mainPic.flatMap(URL.init(string:)).flatMap {
                $0.scheme?.lowercased() == "https" && $0.host?.isEmpty == false
                    && $0.user == nil && $0.password == nil ? $0 : nil
            }
            return SearchProductSummary(
                id: dto.id, title: dto.title, subtitle: dto.subTitle,
                imageURL: url, priceYuan: dto.price, sold: dto.sold, status: dto.status)
        }
    }
    private struct ProductDTO: Decodable {
        let id: Int64; let title: String; let subTitle: String?; let mainPic: String?
        let price: Decimal; let sold: Int64?; let status: Int?
    }
}
