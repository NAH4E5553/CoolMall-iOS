import Foundation

/// H0 v0.2 home read contract: a read-only, cancellable aggregate fetch.
/// No paging, no credentials, no caching, no retries behind this protocol.
public protocol HomeLoading: Sendable {
    func loadHome() async throws -> HomeSnapshot
}

/// Read-only projection of GET page/home. The six display arrays drive the
/// home page; `allCategories` is a mapping auxiliary only and never makes the
/// display non-empty on its own.
public struct HomeSnapshot: Equatable, Sendable {
    public let banners: [HomeBanner]
    public let categories: [HomeCategory]
    public let allCategories: [HomeCategory]
    public let featured: [HomeProductSummary]
    public let recommendations: [HomeProductSummary]
    public let goods: [HomeProductSummary]
    public let coupons: [HomeCouponSummary]

    public init(
        banners: [HomeBanner],
        categories: [HomeCategory],
        allCategories: [HomeCategory],
        featured: [HomeProductSummary],
        recommendations: [HomeProductSummary],
        goods: [HomeProductSummary],
        coupons: [HomeCouponSummary]
    ) {
        self.banners = banners
        self.categories = categories
        self.allCategories = allCategories
        self.featured = featured
        self.recommendations = recommendations
        self.goods = goods
        self.coupons = coupons
    }
}

/// Home carousel entry. `path` is intentionally not modeled (not executable).
public struct HomeBanner: Equatable, Sendable {
    public let id: Int64
    public let description: String
    public let imageURL: URL?

    public init(id: Int64, description: String, imageURL: URL?) {
        self.id = id
        self.description = description
        self.imageURL = imageURL
    }
}

/// Home category chip (HOME-11 will reuse the full tree auxiliary).
public struct HomeCategory: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let parentID: Int64?
    public let imageURL: URL?

    public init(id: Int64, name: String, parentID: Int64?, imageURL: URL?) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.imageURL = imageURL
    }
}

/// One product card projection (carousel/featured/recommend/goods sections).
/// `priceYuan` is the lossless yuan value of the integer response price; it is
/// a home-display value, not an order/coupon/shipping unit.
public struct HomeProductSummary: Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?
    public let priceYuan: Decimal

    public init(id: Int64, title: String, subtitle: String?, imageURL: URL?, priceYuan: Decimal) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.priceYuan = priceYuan
    }
}

/// Coupon title projection; claimability/conditions are out of scope (H0).
public struct HomeCouponSummary: Equatable, Sendable {
    public let id: Int64
    public let title: String

    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
    }
}

/// Recoverable home read failures surfaced to the page model. Carries no raw
/// body, URL, token or backend message; unknown business codes stay opaque
/// and are never re-labeled as authentication failures.
public enum HomeLoadFailure: Error, Equatable, Sendable {
    case networkUnavailable
    case timeout
    case httpStatus(Int)
    case businessCode(Int)
    case invalidConfiguration
    case invalidResponse
    case invalidPayload
}
