import MallCore
import Observation

/// View identity owns the projection; .task owns observation and cancellation.
@MainActor @Observable
final class CartFixtureViewModel {
    private(set) var snapshot: CartSnapshot?
    private let cart: any CartObserving
    private var generation = 0
    init(cart: any CartObserving) { self.cart = cart }
    func observe() async {
        generation += 1
        let request = generation
        let stream = await cart.snapshots()
        for await value in stream {
            guard !Task.isCancelled, request == generation else { return }
            if let current = snapshot, current.scope == value.scope,
                current.revision > value.revision
            {
                continue
            }
            snapshot = value
        }
    }
}
