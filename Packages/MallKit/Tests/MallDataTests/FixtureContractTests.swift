import Foundation
import MallCore
@testable import MallData
import Testing

private let scope = CartScope(environment: "fixture", accountID: nil)
private let item = CartItemID(productID: 1, specificationID: 1)

@Test func bundledProductAndMissingID() async throws {
    let products = FixtureProductService()
    #expect(try await products.product(id: 1).title == "CoolMall 工程验证商品")
    await #expect(throws: FixtureError.self) { try await products.product(id: 2) }
}

@Test func initialAndSubsequentSnapshotsAndReconnect() async throws {
    let store = FakeCartStore(scope: scope)
    var first = await store.snapshots().makeAsyncIterator()
    var second = await store.snapshots().makeAsyncIterator()
    #expect(await first.next()?.revision == 0)
    #expect(await second.next()?.revision == 0)
    try await store.setQuantity(2, for: item)
    #expect(await first.next()?.quantities[item] == 2)
    #expect(await second.next()?.revision == 1)
    var reconnect = await store.snapshots().makeAsyncIterator()
    #expect(await reconnect.next()?.quantities[item] == 2)
    try await store.setQuantity(0, for: item)
    #expect(await first.next()?.quantities.isEmpty == true)
}

@Test func failuresDoNotCommitAndScopesAreIndependent() async throws {
    let failed = FakeCartStore(scope: scope, rejectsWrites: true)
    await #expect(throws: CartError.writeFailed) { try await failed.setQuantity(1, for: item) }
    var failedValues = await failed.snapshots().makeAsyncIterator()
    #expect(await failedValues.next()?.revision == 0)
    let guest = FakeCartStore(scope: scope)
    await #expect(throws: CartError.invalidQuantity) { try await guest.setQuantity(-1, for: item) }
    try await guest.setQuantity(3, for: item)
    let account = FakeCartStore(scope: CartScope(environment: "fixture", accountID: "A"))
    var accountValues = await account.snapshots().makeAsyncIterator()
    #expect(await accountValues.next()?.quantities.isEmpty == true)
}

@Test func cancelledWriteDoesNotCommit() async {
    let store = FakeCartStore(scope: scope)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        await #expect(throws: CancellationError.self) { try await store.setQuantity(1, for: item) }
    }
    await task.value
    var values = await store.snapshots().makeAsyncIterator()
    #expect(await values.next()?.revision == 0)
}

@Test func cancelledObservationCleansUp() async {
    let store = FakeCartStore(scope: scope)
    let task = Task { for await _ in await store.snapshots() {} }
    while await store.subscriberCount == 0 { await Task.yield() }
    task.cancel()
    await task.value
    // Bounded scheduling yields for the explicitly documented termination cleanup task.
    for _ in 0..<1000 {
        if await store.subscriberCount == 0 { break }
        await Task.yield()
    }
    #expect(await store.subscriberCount == 0)
}

@Test func destroyingOwnerFinishesStream() async {
    var store: FakeCartStore? = FakeCartStore(scope: scope)
    let stream = await store?.snapshots()
    store = nil
    var iterator = stream?.makeAsyncIterator()
    #expect(await iterator?.next()?.revision == 0)
    #expect(await iterator?.next() == nil)
}
