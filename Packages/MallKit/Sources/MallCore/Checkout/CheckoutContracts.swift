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
