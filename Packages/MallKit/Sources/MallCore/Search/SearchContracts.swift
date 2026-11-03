import Foundation

/// Immutable query identity. Category order has no semantic meaning; the API receives sorted IDs.
public struct SearchQuery: Equatable, Sendable {
    public let keyword: String
    /// Home featured collection; false means no featured filter, never featured=false on the wire.
    public let featuredOnly: Bool
    public let categoryIDs: [Int64]
    public let minimumPrice: Decimal?
    public let maximumPrice: Decimal?
    public let sort: SearchSort
    public init(
        keyword: String, categoryIDs: [Int64] = [], minimumPrice: Decimal? = nil,
        maximumPrice: Decimal? = nil, sort: SearchSort = .comprehensive, featuredOnly: Bool = false
    ) {
        self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        self.featuredOnly = featuredOnly
        self.categoryIDs = Array(Set(categoryIDs)).sorted()
        self.minimumPrice = minimumPrice; self.maximumPrice = maximumPrice; self.sort = sort
    }
    public var isValid: Bool {
        if let minimumPrice, let maximumPrice, minimumPrice > maximumPrice { return false }
        return (!keyword.isEmpty || featuredOnly) && categoryIDs.allSatisfy { $0 > 0 }
            && [minimumPrice, maximumPrice].compactMap { $0 }.allSatisfy { !$0.isNaN && $0 >= 0 }
    }
}
public enum SearchSort: Equatable, Sendable {
    case comprehensive, salesAscending, salesDescending, priceAscending, priceDescending
}
public struct SearchProductSummary: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?
    public let priceYuan: Decimal
    public let sold: Int64?
    public let status: Int?
    public init(
        id: Int64, title: String, subtitle: String?, imageURL: URL?, priceYuan: Decimal,
        sold: Int64?, status: Int? = nil
    ) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.imageURL = imageURL
        self.priceYuan = priceYuan; self.sold = sold; self.status = status
    }
}
public protocol SearchKeywordsLoading: Sendable {
    func loadSearchKeywords() async throws -> [String]
}
public protocol ProductSearchLoading: Sendable {
    func search(_ query: SearchQuery, page: Int, pageSize: Int) async throws
        -> NumberedPage<SearchProductSummary>
}
public struct SearchHistoryScope: Hashable, Codable, Sendable {
    public let environment: String
    public let accountID: String?
    public init(environment: String, accountID: String?) {
        self.environment = environment; self.accountID = accountID
    }
}
public struct SearchHistorySnapshot: Equatable, Sendable {
    public let keywords: [String]
    public let revision: UInt64
    public init(keywords: [String], revision: UInt64) {
        self.keywords = keywords; self.revision = revision
    }
}
public enum SearchHistoryFailure: Error, Equatable, Sendable { case readFailed, writeFailed }
public protocol SearchHistoryRecording: Sendable {
    var scope: SearchHistoryScope { get }
    func record(_ keyword: String) async throws
}
/// Initial committed snapshot and subsequent commits are delivered without a subscription gap.
public protocol SearchHistoryObserving: Sendable {
    var scope: SearchHistoryScope { get }
    func changes() async throws -> AsyncStream<SearchHistorySnapshot>
    func clear() async throws
}
public protocol SearchHistoryStoring: SearchHistoryRecording, SearchHistoryObserving {}
