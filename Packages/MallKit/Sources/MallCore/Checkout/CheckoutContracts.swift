import Foundation

/// Immutable, single-product navigation input. It is never persisted or written into the cart.
/// The checkout page owns subsequent selections. The ID identifies one purchase route.
public struct BuyNowIntent: Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let productID: Int64
    public let specificationID: Int64
    public let title: String
    public let specification: String
    public let imageURL: URL?
    public let unitPriceYuan: Decimal
    public let quantity: Int64
    public let stock: Int64
    public let productImageURL: URL?
    public let specificationImages: [URL]
    public let subtotalYuan: Decimal
    public init(
        product: ProductDetailSnapshot, specification: ProductSpecification,
        quantity: Int64
    ) throws {
        guard product.id > 0, product.isAvailable, specification.id > 0,
            specification.productID == product.id, quantity > 0, quantity <= specification.stock,
            !product.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ShoppingCartFailure.unavailable
        }
        let price = try CartMoney(yuan: specification.priceYuan)
        let subtotal = try price.multiplied(by: quantity)
        id = UUID(); productID = product.id; specificationID = specification.id
        title = product.title; self.specification = specification.name
        imageURL = specification.imageURLs.first ?? product.imageURLs.first
        stock = specification.stock; productImageURL = product.imageURLs.first
        specificationImages = specification.imageURLs
        unitPriceYuan = price.yuan; self.quantity = quantity; subtotalYuan = subtotal.yuan
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
/// Address/coupon candidates only. This endpoint supplies no quote, freight or eligibility result.
public struct CheckoutContext: Equatable, Sendable {
    public let defaultAddress: ShippingAddress?
    public let coupons: [UserCoupon]?
    public init(defaultAddress: ShippingAddress?, coupons: [UserCoupon]?) {
        self.defaultAddress = defaultAddress; self.coupons = coupons
    }
}
public protocol CheckoutLoading: Sendable {
    func loadCheckout(accountID: Int64) async throws -> CheckoutContext
}

/// Client estimate only; the created order remains the source of payable money.
public struct CheckoutEstimate: Equatable, Sendable {
    public let discountYuan: Decimal
    public let totalYuan: Decimal
    public init(subtotalYuan: Decimal, coupon: UserCoupon?, now: Date = Date()) throws {
        let subtotal = try CartMoney(yuan: subtotalYuan)
        var discount = CartMoney.zero
        if let coupon {
            guard coupon.availability(at: now) == .available,
                let minimum = coupon.minimumSpendYuan,
                subtotal >= (try CartMoney(yuan: minimum))
            else { throw OrderWriteFailure.invalidInput }
            discount = min(try CartMoney(yuan: coupon.amountYuan), subtotal)
        }
        discountYuan = discount.yuan; totalYuan = subtotal.yuan - discount.yuan
    }
}
public struct OrderCreation: Sendable {
    public let intent: BuyNowIntent
    public let addressID: Int64
    public let coupon: UserCoupon?
    public let remark: String
    public init(intent: BuyNowIntent, addressID: Int64, coupon: UserCoupon?, remark: String) {
        self.intent = intent; self.addressID = addressID; self.coupon = coupon; self.remark = remark
    }
}
public protocol OrderCreating: Sendable {
    /// Returns an established server identity even when monetary fields need re-reading.
    func createOrder(accountID: Int64, input: OrderCreation) async throws -> Int64
    /// Local established receipt only. Never dispatches or looks up a speculative order.
    func knownCreatedOrder(accountID: Int64, intentID: UUID) async throws -> Int64?
}
extension OrderCreating {
    public func knownCreatedOrder(accountID: Int64, intentID: UUID) async throws -> Int64? { nil }
}
public enum OrderWriteFailure: Error, Equatable, Sendable {
    case authenticationRequired, invalidInput, unavailable, busy, unconfirmed
    case rejected(code: Int, message: String?)
    public var message: String {
        switch self {
        case .authenticationRequired: "请重新登录"
        case .invalidInput: "请检查地址、商品和优惠券信息"
        case .unavailable: "当前操作暂不可用"
        case .busy: "正在处理，请勿重复提交"
        case .unconfirmed: "操作结果尚未确认，请到我的订单查看，请勿重复提交"
        case .rejected(_, let message): message ?? "操作失败，请稍后重试"
        }
    }
}
