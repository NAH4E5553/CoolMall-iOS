import Foundation

public enum CouponAvailability: Equatable, Sendable {
    case available, used, expired, disabled, upcoming, unverified
}
/// Owned coupon, using exact yuan amounts. Unknown wire states never imply eligibility.
public struct UserCoupon: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let description: String
    public let amountYuan: Decimal
    public let minimumSpendYuan: Decimal?
    public let startTime: String?
    public let endTime: String?
    public let type: Int?
    public let status: Int?
    public let useStatus: Int?
    public init(
        id: Int64, title: String, description: String, amountYuan: Decimal,
        minimumSpendYuan: Decimal?, startTime: String?, endTime: String?,
        type: Int?, status: Int?, useStatus: Int?
    ) {
        self.id = id; self.title = title; self.description = description;
        self.amountYuan = amountYuan
        self.minimumSpendYuan = minimumSpendYuan; self.startTime = startTime; self.endTime = endTime
        self.type = type; self.status = status; self.useStatus = useStatus
    }
    public func availability(at now: Date = Date(), timeZone: TimeZone = .current)
        -> CouponAvailability
    {
        if useStatus == 1 { return .used }
        if useStatus == 2 { return .expired }
        guard type == 0, status == 1, useStatus == 0 else {
            return status == 0 ? .disabled : .unverified
        }
        // No confirmed unlimited-validity contract: absent bounds remain unverified.
        guard let endTime, !endTime.isEmpty, let startTime, !startTime.isEmpty,
            let end = Self.date(endTime, timeZone: timeZone),
            let start = Self.date(startTime, timeZone: timeZone), start < end
        else { return .unverified }
        if now >= end { return .expired }
        if now < start { return .upcoming }
        return .available
    }
    private static func date(_ text: String, timeZone: TimeZone) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = iso.date(from: text) { return value }
        iso.formatOptions = [.withInternetDateTime]
        if let value = iso.date(from: text) { return value }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = timeZone; f.isLenient = false
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ] {
            f.dateFormat = format
            if let value = f.date(from: text), f.string(from: value) == text { return value }
        }
        return nil
    }
}
public protocol UserCouponsLoading: Sendable {
    func loadCoupons(accountID: Int64, page: Int, pageSize: Int) async throws -> NumberedPage<
        UserCoupon
    >
}
/// Product prices are yuan, following Goods.price. This is price-filter browsing, not SKU eligibility.
public struct CouponProductSummary: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?
    public let priceYuan: Decimal
    public let sold: Int64
    public init(
        id: Int64, title: String, subtitle: String?, imageURL: URL?, priceYuan: Decimal, sold: Int64
    ) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.imageURL = imageURL
        self.priceYuan = priceYuan; self.sold = sold
    }
}
public protocol CouponProductsLoading: Sendable {
    func loadProducts(minimumPriceYuan: Decimal?, page: Int, pageSize: Int) async throws
        -> NumberedPage<CouponProductSummary>
}
