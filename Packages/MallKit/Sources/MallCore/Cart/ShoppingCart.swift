import Foundation

/// Exact nonnegative CNY amount. Conversion never rounds incoming prices.
public struct CartMoney: Equatable, Comparable, Codable, Sendable {
    public let cents: Int64
    public init(yuan: Decimal) throws {
        let scaled = yuan * 100
        var value = scaled
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard !scaled.isNaN, scaled >= 0, scaled <= Decimal(Int64.max), rounded == scaled,
            let cents = Int64(NSDecimalNumber(decimal: scaled).stringValue)
        else { throw ShoppingCartFailure.invalidMoney }
        self.cents = cents
    }
    private enum CodingKeys: String, CodingKey { case cents }
    public init(from decoder: any Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self).decode(
            Int64.self, forKey: .cents)
        guard value >= 0 else { throw ShoppingCartFailure.invalidMoney }
        cents = value
    }
    public var yuan: Decimal { Decimal(cents) / 100 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.cents < rhs.cents }
    public static var zero: Self { Self(cents: 0) }
    private init(cents: Int64) { self.cents = cents }
    public func multiplied(by quantity: Int64) throws -> Self {
        let (result, overflow) = cents.multipliedReportingOverflow(by: quantity)
        guard quantity >= 0, !overflow else { throw ShoppingCartFailure.invalidMoney }
        return Self(cents: result)
    }
    public func adding(_ other: Self) throws -> Self {
        let (result, overflow) = cents.addingReportingOverflow(other.cents)
        guard !overflow else { throw ShoppingCartFailure.invalidMoney }
        return Self(cents: result)
    }
    public var formatted: String {
        yuan.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
    }
}

public struct CartLine: Equatable, Codable, Sendable, Identifiable {
    public let productID: Int64
    public let specificationID: Int64
    public let title: String
    public let specification: String
    public let imageURL: URL?
    public let unitPrice: CartMoney
    public let quantity: Int64
    public let checkedStock: Int64
    public var id: CartItemID { .init(productID: productID, specificationID: specificationID) }
    public init(quote: CartQuote, quantity: Int64) {
        productID = quote.productID; specificationID = quote.specificationID
        title = quote.title; specification = quote.specification; imageURL = quote.imageURL
        unitPrice = quote.price; checkedStock = quote.stock; self.quantity = quantity
    }
    public func withQuantity(_ quantity: Int64) -> Self {
        Self(quote: quote, quantity: quantity)
    }
    public var quote: CartQuote {
        .init(
            productID: productID, specificationID: specificationID, title: title,
            specification: specification, imageURL: imageURL, price: unitPrice, stock: checkedStock)
    }
}

public struct CartQuote: Equatable, Sendable {
    public let productID: Int64
    public let specificationID: Int64
    public let title: String
    public let specification: String
    public let imageURL: URL?
    public let price: CartMoney
    public let stock: Int64
    public init(
        productID: Int64, specificationID: Int64, title: String, specification: String,
        imageURL: URL?, price: CartMoney, stock: Int64
    ) {
        self.productID = productID; self.specificationID = specificationID; self.title = title
        self.specification = specification; self.imageURL = imageURL; self.price = price;
        self.stock = stock
    }
    public var id: CartItemID { .init(productID: productID, specificationID: specificationID) }
}

public struct CartProductCheck: Sendable {
    public let productID: Int64
    public let isAvailable: Bool
    public let quotes: [CartQuote]
    public init(productID: Int64, isAvailable: Bool, quotes: [CartQuote]) {
        self.productID = productID; self.isAvailable = isAvailable; self.quotes = quotes
    }
    public func quote(for item: CartItemID) throws -> CartQuote {
        guard productID == item.productID, isAvailable,
            let quote = quotes.first(where: { $0.specificationID == item.specificationID })
        else { throw ShoppingCartFailure.unavailable }
        guard quote.stock > 0 else { throw ShoppingCartFailure.insufficientStock(available: 0) }
        return quote
    }
}

public enum ShoppingCartFailure: Error, Equatable, Sendable {
    case invalidQuantity, invalidMoney, unavailable, missingLine, staleRevision
    case insufficientStock(available: Int64)
    case priceChanged(old: CartMoney, new: CartMoney)
    case readFailed, writeFailed
}

/// One immutable committed revision. Selection and live verification are page drafts.
public struct ShoppingCartSnapshot: Equatable, Sendable {
    public let scope: CartScope
    public let revision: UInt64
    public let lines: [CartLine]
    public init(scope: CartScope, revision: UInt64, lines: [CartLine]) {
        self.scope = scope; self.revision = revision; self.lines = lines
    }
    public var quantities: [CartItemID: Int64] {
        Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.quantity) })
    }
    public func total(for ids: Set<CartItemID>) throws -> CartMoney {
        try lines.filter { ids.contains($0.id) }.reduce(.zero) {
            try $0.adding($1.unitPrice.multiplied(by: $1.quantity))
        }
    }
    public func itemCount() throws -> Int64 {
        try lines.reduce(0) {
            let (count, overflow) = $0.addingReportingOverflow($1.quantity)
            guard !overflow else { throw ShoppingCartFailure.invalidQuantity }
            return count
        }
    }
}

public protocol CartProductChecking: Sendable {
    func check(productID: Int64) async throws -> CartProductCheck
}

/// App-owned, scope-bound single writer. Values are published only after disk save.
/// Network checks occur outside its serialized transaction. A check is not a reservation.
public protocol ShoppingCart: Sendable {
    var scope: CartScope { get }
    func observe() async throws -> AsyncStream<ShoppingCartSnapshot>
    func current() async throws -> ShoppingCartSnapshot
    func add(quantity: Int64, quote: CartQuote, confirmedPrice: CartMoney?, operationID: UUID)
        async throws
    func increase(
        _ item: CartItemID, quote: CartQuote, confirmedPrice: CartMoney?, expectedRevision: UInt64)
        async throws
    func decrease(_ item: CartItemID, expectedRevision: UInt64) async throws
    func remove(_ items: Set<CartItemID>, expectedRevision: UInt64) async throws
}
