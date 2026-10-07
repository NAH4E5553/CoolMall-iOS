@testable import CartFeature
import MallCore
import Testing

private struct Cart: CartObserving {
    let values: [CartSnapshot]
    func snapshots() async -> AsyncStream<CartSnapshot> {
        AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
}

@Test @MainActor func projectionRejectsOlderRevision() async {
    let scope = CartScope(environment: "fixture", accountID: nil)
    let latest = CartSnapshot(
        scope: scope, revision: 2, quantities: [CartItemID(productID: 1, specificationID: 1): 3])
    let stale = CartSnapshot(scope: scope, revision: 1, quantities: [:])
    let model = CartFixtureViewModel(cart: Cart(values: [latest, stale]))
    await model.observe()
    #expect(model.snapshot == latest)
}

@Test @MainActor func cancellationDoesNotPublishBufferedValues() async {
    let scope = CartScope(environment: "fixture", accountID: nil)
    let model = CartFixtureViewModel(
        cart: Cart(values: [CartSnapshot(scope: scope, revision: 0, quantities: [:])]))
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        await model.observe()
    }
    await task.value
    #expect(model.snapshot == nil)
}
