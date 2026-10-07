import Foundation

/// A store instance is bound to one environment and account (nil means guest).
public struct CartScope: Equatable, Sendable {
    public let environment: String
    public let accountID: String?
    public init(environment: String, accountID: String?) {
        self.environment = environment; self.accountID = accountID
    }
}

/// A specification is part of the identity, even when products share an ID.
public struct CartItemID: Hashable, Sendable {
    public let productID: Int64
    public let specificationID: Int64
    public init(productID: Int64, specificationID: Int64) {
        self.productID = productID; self.specificationID = specificationID
    }
}

/// Immutable committed state. UI consumers cannot mutate the owner's records.
public struct CartSnapshot: Equatable, Sendable {
    public let scope: CartScope
    public let revision: UInt64
    public let quantities: [CartItemID: Int]
    public init(scope: CartScope, revision: UInt64, quantities: [CartItemID: Int]) {
        self.scope = scope; self.revision = revision; self.quantities = quantities
    }
}

public enum CartError: Error, Equatable { case invalidQuantity; case writeFailed }

/// Quantity zero removes a line; negative quantities fail. Returns only after commit.
/// Implementations check cancellation before commit. No automatic retry is implied.
public protocol CartCommands: Sendable {
    func setQuantity(_ quantity: Int, for item: CartItemID) async throws
}

/// Atomically registers a subscriber and supplies current state, followed by updates.
/// Slow consumers may skip revisions, never regress. Cancellation removes the subscription.
public protocol CartObserving: Sendable {
    func snapshots() async -> AsyncStream<CartSnapshot>
}
