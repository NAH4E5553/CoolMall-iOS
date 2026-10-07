import Foundation
import MallCore

/// F0 memory-only fake. App owns one instance; scope is immutable for its lifetime.
/// This actor alone commits quantities/revision. No disk commit or session switching exists.
public actor FakeCartStore: CartCommands, CartObserving {
    private let scope: CartScope
    private let rejectsWrites: Bool
    private var revision: UInt64 = 0
    private var quantities: [CartItemID: Int] = [:]
    private var subscribers: [UUID: AsyncStream<CartSnapshot>.Continuation] = [:]
    var subscriberCount: Int { subscribers.count }

    public init(scope: CartScope, rejectsWrites: Bool = false) {
        self.scope = scope; self.rejectsWrites = rejectsWrites
    }

    public func setQuantity(_ quantity: Int, for item: CartItemID) async throws {
        try Task.checkCancellation()
        guard quantity >= 0 else { throw CartError.invalidQuantity }
        guard !rejectsWrites else { throw CartError.writeFailed }
        quantities[item] = quantity == 0 ? nil : quantity
        revision += 1
        for subscriber in subscribers.values { subscriber.yield(snapshot) }
    }

    public func snapshots() -> AsyncStream<CartSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<CartSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(snapshot)
        // A short cleanup task belongs to the stream termination, captures the owner weakly.
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    private var snapshot: CartSnapshot {
        CartSnapshot(scope: scope, revision: revision, quantities: quantities)
    }
    private func removeSubscriber(_ id: UUID) { subscribers[id] = nil }
    deinit { for subscriber in subscribers.values { subscriber.finish() } }
}
