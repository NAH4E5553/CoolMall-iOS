import Foundation

public struct FootprintScope: Hashable, Codable, Sendable {
    public let environment: String
    public let accountID: String?
    public init(environment: String, accountID: String?) {
        self.environment = environment; self.accountID = accountID
    }
}
public struct FootprintItem: Identifiable, Equatable, Codable, Sendable {
    public let id: Int64
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?
    public let priceYuan: Decimal
    public let sold: Int64
    public let viewedAt: Date
    public init(
        id: Int64, title: String, subtitle: String?, imageURL: URL?, priceYuan: Decimal,
        sold: Int64, viewedAt: Date
    ) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.imageURL = imageURL
        self.priceYuan = priceYuan; self.sold = sold; self.viewedAt = viewedAt
    }
    public init(detail: ProductDetailSnapshot, viewedAt: Date = Date()) {
        self.init(
            id: detail.id, title: detail.title, subtitle: detail.subtitle,
            imageURL: detail.imageURLs.first, priceYuan: detail.priceYuan, sold: detail.sold,
            viewedAt: viewedAt)
    }
}
public struct FootprintPage: Equatable, Sendable {
    public let items: [FootprintItem]
    public let total: Int
    public let revision: UInt64
    public let nextOffset: Int?
    public init(items: [FootprintItem], total: Int, revision: UInt64, nextOffset: Int?) {
        self.items = items; self.total = total; self.revision = revision;
        self.nextOffset = nextOffset
    }
}
public enum FootprintFailure: Error, Equatable, Sendable {
    case readFailed, writeFailed, invalidRecord, invalidPage
}
public protocol FootprintRecording: Sendable {
    func record(_ item: FootprintItem) async throws
}
public protocol FootprintBrowsing: Sendable {
    var scope: FootprintScope { get }
    func page(offset: Int, limit: Int) async throws -> FootprintPage
    func changes() async throws -> AsyncStream<UInt64>
    func clear() async throws
}
public protocol FootprintStoring: FootprintRecording, FootprintBrowsing {}
