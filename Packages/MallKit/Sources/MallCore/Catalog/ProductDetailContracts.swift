import Foundation

/// A current product's immutable browsing projection. Prices are exact yuan,
/// not order totals. Empty image arrays mean an explicit placeholder.
public struct ProductDetailSnapshot: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let title: String
    public let subtitle: String?
    public let priceYuan: Decimal
    public let sold: Int64
    public let isAvailable: Bool
    public let imageURLs: [URL]
    public let contentImageURLs: [URL]
    public let coupons: [ProductDetailCoupon]
    public let reviews: [ProductDetailReview]

    public init(
        id: Int64, title: String, subtitle: String?, priceYuan: Decimal,
        sold: Int64, isAvailable: Bool, imageURLs: [URL], contentImageURLs: [URL],
        coupons: [ProductDetailCoupon] = [], reviews: [ProductDetailReview] = []
    ) {
        self.id = id; self.title = title; self.subtitle = subtitle
        self.priceYuan = priceYuan; self.sold = sold; self.isAvailable = isAvailable
        self.imageURLs = imageURLs; self.contentImageURLs = contentImageURLs
        self.coupons = coupons; self.reviews = reviews
    }
}

/// One complete, single-select SKU; the server's list order is preserved.
public struct ProductSpecification: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let productID: Int64
    public let name: String
    public let priceYuan: Decimal
    public let stock: Int64
    public let imageURLs: [URL]

    public init(
        id: Int64, productID: Int64, name: String, priceYuan: Decimal,
        stock: Int64, imageURLs: [URL]
    ) {
        self.id = id; self.productID = productID; self.name = name
        self.priceYuan = priceYuan; self.stock = stock; self.imageURLs = imageURLs
    }
}

/// Independent anonymous reads. No page cache, automatic retry or cart write.
/// Invalid IDs fail before I/O; cancellation remains CancellationError.
public protocol ProductDetailLoading: Sendable {
    func loadDetail(productID: Int64) async throws -> ProductDetailSnapshot
    func loadSpecifications(productID: Int64) async throws -> [ProductSpecification]
}

public enum ProductDetailLoadFailure: Error, Equatable, Sendable {
    case invalidProductID
    case invalidConfiguration
    case networkUnavailable
    case timeout
    case httpStatus(Int)
    case businessCode(Int)
    case invalidResponse
}

/// Read-only coupon presentation from the current detail response; no receive command.
public struct ProductDetailCoupon: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let title: String
    public let description: String
    public let amountYuan: Decimal
    public let minimumSpendYuan: Decimal?
    public let endTime: String?

    public init(
        id: Int64, title: String, description: String, amountYuan: Decimal,
        minimumSpendYuan: Decimal?, endTime: String?
    ) {
        self.id = id; self.title = title; self.description = description
        self.amountYuan = amountYuan; self.minimumSpendYuan = minimumSpendYuan
        self.endTime = endTime
    }
}

/// A real product-bound review, shared by the detail summary and paged review list.
public struct ProductDetailReview: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let productID: Int64
    public let content: String
    public let starCount: Int
    public let nickname: String?
    public let avatarURL: URL?
    public let imageURLs: [URL]
    public let createdAt: String?

    public init(
        id: Int64, productID: Int64, content: String, starCount: Int,
        nickname: String?, avatarURL: URL?, imageURLs: [URL], createdAt: String? = nil
    ) {
        self.id = id; self.productID = productID; self.content = content
        self.starCount = starCount; self.nickname = nickname
        self.avatarURL = avatarURL; self.imageURLs = imageURLs; self.createdAt = createdAt
    }
}
