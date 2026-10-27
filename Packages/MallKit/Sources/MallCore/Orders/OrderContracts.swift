import Foundation

/// Filter values follow the Android wire request, never UI tab indices.
public enum OrderFilter: String, CaseIterable, Hashable, Sendable {
    case all, unpaid, unshipped, unreceived, afterSale, unevaluated, completed
    public var wireStatuses: [Int]? {
        switch self {
        case .all: nil
        case .unpaid: [0]
        case .unshipped: [1]
        case .unreceived: [2]
        case .afterSale: [5, 6]
        case .unevaluated: [3]
        case .completed: [4]
        }
    }
}
/// A historical value snapshot; it need not have a current address-book identity.
public struct OrderAddressSnapshot: Equatable, Sendable {
    public let contact: String?
    public let phone: String?
    public let isDefault: Bool?
    public let location: String
    public init(contact: String?, phone: String?, location: String, isDefault: Bool? = nil) {
        self.contact = contact; self.phone = phone; self.location = location;
        self.isDefault = isDefault
    }
}
public struct OrderLineSnapshot: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let title: String?
    public let specification: String?
    public let imageURL: URL?
    public let unitPriceYuan: Decimal?
    public let quantity: Int64
    public init(
        id: Int64, title: String?, specification: String?, imageURL: URL?, quantity: Int64,
        unitPriceYuan: Decimal? = nil
    ) {
        self.id = id; self.title = title; self.specification = specification
        self.imageURL = imageURL; self.quantity = quantity; self.unitPriceYuan = unitPriceYuan
    }
}
/// Immutable server history; absent monetary fields never become a zero quote.
public struct OrderSnapshot: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let number: String?
    public let status: Int
    public let title: String?
    public let createdAt: String?
    public let paidAt: String?
    public let address: OrderAddressSnapshot?
    public let lines: [OrderLineSnapshot]?
    public let amounts: OrderAmounts?
    public let payType: Int?
    public let remark: String?
    public let closeRemark: String?
    public init(
        id: Int64, number: String?, status: Int, title: String?, createdAt: String?,
        paidAt: String?, address: OrderAddressSnapshot?, lines: [OrderLineSnapshot]?,
        amounts: OrderAmounts? = nil, payType: Int? = nil, remark: String? = nil,
        closeRemark: String? = nil
    ) {
        self.id = id; self.number = number; self.status = status; self.title = title
        self.createdAt = createdAt; self.paidAt = paidAt; self.address = address; self.lines = lines
        self.amounts = amounts; self.payType = payType; self.remark = remark;
        self.closeRemark = closeRemark
    }
}
public protocol OrdersLoading: Sendable {
    func loadOrders(accountID: Int64, filter: OrderFilter, page: Int, pageSize: Int) async throws
        -> NumberedPage<OrderSnapshot>
    func loadOrder(accountID: Int64, orderID: Int64) async throws -> OrderSnapshot
}

public struct OrderAmounts: Equatable, Sendable {
    public let subtotalYuan: Decimal
    public let discountYuan: Decimal
    public var payableYuan: Decimal { subtotalYuan - discountYuan }
    public init(subtotalYuan: Decimal, discountYuan: Decimal) throws {
        let subtotal = try CartMoney(yuan: subtotalYuan),
            discount = try CartMoney(yuan: discountYuan)
        guard discount <= subtotal else { throw ShoppingCartFailure.invalidMoney }
        self.subtotalYuan = subtotal.yuan; self.discountYuan = discount.yuan
    }
}
public struct OrderCancelReason: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public init(id: Int64, name: String) { self.id = id; self.name = name }
}
public protocol OrderCancelling: Sendable {
    func loadCancelReasons(accountID: Int64) async throws -> [OrderCancelReason]
    func cancelOrder(accountID: Int64, orderID: Int64, reason: OrderCancelReason) async throws
}
