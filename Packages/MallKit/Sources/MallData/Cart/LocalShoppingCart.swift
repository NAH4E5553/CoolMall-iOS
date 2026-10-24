import Foundation
import MallCore

public actor LocalShoppingCart: ShoppingCart {
    public nonisolated let scope: CartScope
    private let url: URL
    private var opened: PersistentCartStore?
    public init(scope: CartScope, url: URL) { self.scope = scope; self.url = url }
    private func owner() throws -> PersistentCartStore {
        if let opened { return opened }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let value = try PersistentCartStore(scope: scope, url: url)
        opened = value
        return value
    }
    public func observe() async throws -> AsyncStream<ShoppingCartSnapshot> {
        try await owner().observe()
    }
    public func current() async throws -> ShoppingCartSnapshot { try await owner().current() }
    public func add(
        quantity: Int64, quote: CartQuote, confirmedPrice: CartMoney?, operationID: UUID
    ) async throws {
        try await owner().add(
            quantity: quantity, quote: quote, confirmedPrice: confirmedPrice,
            operationID: operationID)
    }
    public func increase(
        _ item: CartItemID, quote: CartQuote, confirmedPrice: CartMoney?, expectedRevision: UInt64
    ) async throws {
        try await owner().increase(
            item, quote: quote, confirmedPrice: confirmedPrice, expectedRevision: expectedRevision)
    }
    public func decrease(_ item: CartItemID, expectedRevision: UInt64) async throws {
        try await owner().decrease(item, expectedRevision: expectedRevision)
    }
    public func remove(_ items: Set<CartItemID>, expectedRevision: UInt64) async throws {
        try await owner().remove(items, expectedRevision: expectedRevision)
    }
}
