import Foundation
import MallCore
@testable import CartFeature
import Testing

@Suite @MainActor struct CartViewModelTests {
    @Test func entryVerificationDoesNotInsertTransientNotesButFailuresRemainVisible() async throws {
        let q = try quote(), store = TestCart([.init(quote: try quote(), quantity: 1)])
        let verifier = TestVerifier([q]), model = CartViewModel(store: store, verifier: verifier)
        await verifier.suspend()
        let first = Task { await model.observe() }
        await waitUntil { await verifier.gate != nil }
        #expect(model.note(for: CartLine(quote: q, quantity: 1)) == nil)
        #expect(model.selectable.isEmpty)
        #expect(model.snapshot?.lines.first?.quantity == 1)
        await verifier.release(); await waitUntil { model.checks[1] != nil }
        model.stop(); first.cancel()
        await verifier.suspend()
        let returned = Task { await model.observe() }
        defer { model.stop(); returned.cancel() }
        await waitUntil { await verifier.gate != nil }
        #expect(model.note(for: CartLine(quote: q, quantity: 1)) == nil)
        #expect(model.selectable.isEmpty)
        await verifier.release(); await waitUntil { model.checks[1] != nil }
        #expect(model.selectable == [q.id])
        await verifier.fail(); model.retryChecks()
        await waitUntil { model.checkFailures.contains(1) }
        #expect(model.note(for: CartLine(quote: q, quantity: 1)) == "未核验，点击重试")
        #expect(model.selectable.isEmpty)
        #expect(model.snapshot?.lines.first?.quantity == 1)
        #expect(await store.writes == 0)
    }
    @Test func twoHostsShareRowsButNotSelectionOrEditDrafts() async throws {
        let q = try quote(); let q2 = try quote(2)
        let store = TestCart([.init(quote: q, quantity: 2), .init(quote: q2, quantity: 1)])
        let verifier = TestVerifier([q, q2])
        let a = CartViewModel(store: store, verifier: verifier),
            b = CartViewModel(store: store, verifier: verifier)
        let ta = Task { await a.observe() }, tb = Task { await b.observe() }
        defer { a.stop(); b.stop(); ta.cancel(); tb.cancel() }
        await waitUntil { a.selectable.count == 2 && b.selectable.count == 2 }
        a.toggle(q.id)
        #expect(a.selection == [q.id]); #expect(b.selection.isEmpty)
        #expect(a.total?.cents == 20000)
        b.toggleEditing(); b.toggle(q2.id); b.removeSelected()
        await waitUntil { a.snapshot?.lines.count == 1 && b.snapshot?.lines.count == 1 && !b.busy }
        #expect(a.selection == [q.id]); #expect(b.selection.isEmpty); #expect(!b.editing)
        #expect(a.snapshot == b.snapshot)
    }
    @Test func editingClearsSelectionAndInvalidLinesRemainDeletable() async throws {
        let q = try quote(stock: 1)
        let store = TestCart([.init(quote: q, quantity: 2)])
        let model = CartViewModel(store: store, verifier: TestVerifier([q]))
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.checks[1] != nil }
        #expect(model.selectable.isEmpty); #expect(!model.allSelected)
        #expect(model.snapshot?.lines.count == 1)
        model.toggleEditing(); model.toggleAll(); #expect(model.selection == [q.id])
        model.toggleEditing(); #expect(model.selection.isEmpty)
    }
    @Test func increasePriceConfirmationRechecksAndUpdatesWholeRow() async throws {
        let q = try quote(), changed = try quote(price: 120)
        let store = TestCart([.init(quote: q, quantity: 2)]), verifier = TestVerifier([changed])
        let model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.checks[1] != nil }
        model.increase(q.id)
        await waitUntil { model.confirmation != nil }
        #expect(await store.writes == 0)
        model.confirmPrice()
        await waitUntil { model.snapshot?.lines.first?.quantity == 3 }
        #expect(model.snapshot?.lines.first?.unitPrice == changed.price)
        #expect(await verifier.calls >= 3)
    }
    @Test func increaseReturningToStoredPriceStillNeedsAnotherConfirmation() async throws {
        let original = try quote(), verifier = TestVerifier([try quote(price: 120)])
        let store = TestCart([.init(quote: original, quantity: 2)])
        let model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.checks[1] != nil }
        model.increase(original.id)
        await waitUntil { model.confirmation != nil }
        await verifier.replace([original]); model.confirmPrice()
        await waitUntil { model.confirmation != nil || !model.busy }
        #expect(model.confirmation?.new.cents == 10000)
        #expect(await store.writes == 0)
        #expect(model.snapshot?.lines.first?.quantity == 2)
        model.confirmPrice()
        await waitUntil { model.snapshot?.lines.first?.quantity == 3 }
        #expect(await store.writes == 1)
    }
    @Test(arguments: ["zero", "insufficient", "missing", "unavailable"])
    func freshInvalidCheckRemovesExistingBrowseSelection(_ kind: String) async throws {
        let original = try quote(), store = TestCart([.init(quote: try quote(), quantity: 2)])
        let verifier = TestVerifier([original]),
            model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.checks[1] != nil }
        model.toggle(original.id); #expect(model.selection == [original.id])
        let replacement = try quote(stock: kind == "zero" ? 0 : 1)
        await verifier.replace(
            kind == "missing" ? [] : [replacement], available: kind != "unavailable")
        model.increase(original.id)
        await waitUntil { !model.busy }
        #expect(model.selection.isEmpty); #expect(model.selectable.isEmpty)
        #expect(model.note(for: CartLine(quote: original, quantity: 2)) != nil)
        #expect(model.snapshot?.lines == [CartLine(quote: original, quantity: 2)])
        #expect(model.total?.cents == 0); #expect(await store.writes == 0)
        model.toggleEditing(); model.toggleAll()
        #expect(model.selection == [original.id])
    }
    @Test func completeFreshCheckRemovesOtherMissingSkuSelection() async throws {
        let original = try quote(), other = try quote(2)
        let store = TestCart([
            .init(quote: original, quantity: 2), .init(quote: other, quantity: 1),
        ])
        let verifier = TestVerifier([original, other]),
            model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.selectable.count == 2 }
        model.toggleAll(); await verifier.replace([original]); model.increase(original.id)
        await waitUntil { model.snapshot?.lines.first?.quantity == 3 && !model.busy }
        #expect(model.selection == [original.id]); #expect(model.selectable == [original.id])
        #expect(model.note(for: CartLine(quote: other, quantity: 1))?.contains("失效") == true)
        #expect(await store.writes == 1)
    }
    @Test func failedFreshCheckIsUnknownAndCanBeExplicitlyRetried() async throws {
        let original = try quote(), store = TestCart([.init(quote: try quote(), quantity: 2)])
        let verifier = TestVerifier([original]),
            model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.checks[1] != nil }
        model.toggle(original.id); await verifier.fail(); model.increase(original.id)
        await waitUntil { !model.busy }
        #expect(model.checks[1] == nil); #expect(model.checkFailures.contains(1))
        #expect(model.selection.isEmpty); #expect(model.selectable.isEmpty)
        #expect(model.note(for: CartLine(quote: original, quantity: 2)) == "未核验，点击重试")
        #expect(model.snapshot?.lines.first?.quantity == 2); #expect(await store.writes == 0)
        await verifier.replace([original]); model.retryChecks()
        await waitUntil { model.checks[1] != nil }
        #expect(!model.checkFailures.contains(1)); #expect(model.selectable == [original.id])
        #expect(model.selection.isEmpty)
    }
    @Test func olderEntryCheckCannotRestoreNewlyRejectedStock() async throws {
        let original = try quote(), store = TestCart([.init(quote: try quote(), quantity: 2)])
        let verifier = TestVerifier([original]); await verifier.suspend()
        let model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { await verifier.gate != nil }
        await verifier.replace([try quote(stock: 0)]); model.increase(original.id)
        await waitUntil { !model.busy }
        await verifier.release(); await waitUntil { await verifier.released }
        for _ in 0..<20 { await Task.yield() }
        #expect(model.checks[1]?.quotes.first?.stock == 0)
        #expect(model.selectable.isEmpty); #expect(model.selection.isEmpty)
        #expect(await store.writes == 0)
    }
    @Test func failedWriteAndOfflineDecreasePreserveCommittedAmounts() async throws {
        let q = try quote(); let store = TestCart([.init(quote: q, quantity: 2)])
        let verifier = TestVerifier([q]); await verifier.fail()
        let model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.checkFailures.contains(1) }
        model.decrease(q.id)
        await waitUntil { model.snapshot?.lines.first?.quantity == 1 && !model.busy }
        #expect(model.snapshot?.lines.first?.unitPrice == q.price)
        model.toggleEditing(); model.toggleAll(); await store.fail(); model.removeSelected()
        await waitUntil { model.message != nil }
        #expect(model.snapshot?.lines.count == 1); #expect(model.selection == [q.id]);
        #expect(model.editing)
    }
    @Test func explicitRetryRefreshesPreviouslyVerifiedStock() async throws {
        let q = try quote(stock: 1)
        let store = TestCart([.init(quote: q, quantity: 1)]), verifier = TestVerifier([q])
        let model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.checks[1] != nil }
        #expect(!model.canIncrease(CartLine(quote: q, quantity: 1)))
        await verifier.replace([try quote(stock: 5)])
        model.retryChecks()
        await waitUntil { model.checks[1]?.quotes.first?.stock == 5 }
        #expect(model.canIncrease(CartLine(quote: q, quantity: 1)))
    }
    @Test(arguments: [false, true])
    func quantityOwnerRejectsDuplicateAndPeerWritesWithoutBlockingDrafts(_ priceChanges: Bool)
        async throws
    {
        let q = try quote(), peer = try quote(2)
        let store = TestCart([.init(quote: q, quantity: 1), .init(quote: peer, quantity: 2)])
        let verifier = TestVerifier([q, peer]),
            model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.selectable.count == 2 }
        await verifier.replace([try quote(price: priceChanges ? 120 : 100), peer])
        await verifier.suspend(); model.increase(q.id)
        #expect(model.processingItem == q.id); #expect(model.busy); #expect(!model.isRemoving)
        model.increase(q.id); model.decrease(q.id)
        await waitUntil { await verifier.gate != nil }
        model.increase(peer.id)
        #expect(model.message == "当前购物项正在处理，请稍后再操作")
        model.toggleEditing(); #expect(model.editing)
        model.toggle(peer.id); #expect(model.selection == [peer.id])
        model.removeSelected()
        #expect(model.processingItem == q.id); #expect(!model.isRemoving)
        #expect(await store.writes == 0); #expect(await verifier.calls == 2)
        model.toggleEditing(); #expect(!model.editing)
        await verifier.release()
        if priceChanges {
            await waitUntil { model.confirmation != nil }
            #expect(!model.busy); #expect(model.processingItem == nil)
            #expect(model.message == nil); #expect(await store.writes == 0)
            model.confirmPrice()
        }
        await waitUntil { model.snapshot?.lines.first?.quantity == 2 && !model.busy }
        #expect(model.message == nil)
        #expect(model.processingItem == nil); #expect(await store.writes == 1)
        #expect(model.snapshot?.lines.last?.quantity == 2)
        #expect(model.snapshot?.revision == 1)
    }
    @Test(arguments: ["success", "failure", "cancel"])
    func decreaseOwnerClearsOnSaveAndFailureWithoutOptimisticQuantity(_ outcome: String)
        async throws
    {
        let fails = outcome == "failure"
        let q = try quote(), peer = try quote(2)
        let store = TestCart([.init(quote: q, quantity: 2), .init(quote: peer, quantity: 2)])
        let model = CartViewModel(store: store, verifier: TestVerifier([q, peer]))
        let task = Task { await model.observe() }; defer { model.stop(); task.cancel() }
        await waitUntil { model.selectable.count == 2 }
        model.toggle(q.id); await store.suspendWrite()
        if fails { await store.fail() }
        model.decrease(q.id)
        await waitUntil { await store.writeGate != nil }
        #expect(model.processingItem == q.id); #expect(model.busy)
        #expect(model.snapshot?.lines.first?.quantity == 2)
        #expect(model.total?.cents == 20000); #expect(model.snapshot?.revision == 0)
        model.decrease(q.id); model.increase(peer.id)
        #expect(await store.decreaseCalls == 1); #expect(await store.writes == 0)
        if outcome == "cancel" {
            model.stop(); task.cancel()
            #expect(!model.busy); #expect(model.processingItem == nil)
            #expect(model.message == nil)
            await store.releaseWrite(); await waitUntil { await store.finishedDecreases == 1 }
            #expect(await store.writes == 0)
            #expect(model.snapshot?.lines.first?.quantity == 2)
            #expect(model.snapshot?.revision == 0)
            return
        }
        await store.releaseWrite(); await waitUntil { !model.busy }
        #expect(model.processingItem == nil); #expect(!model.isRemoving)
        #expect(model.snapshot?.lines.first?.quantity == (fails ? 2 : 1))
        #expect(model.total?.cents == (fails ? 20000 : 10000))
        #expect(model.snapshot?.revision == (fails ? 0 : 1))
        #expect(model.selection == [q.id]); #expect(await store.writes == (fails ? 0 : 1))
        if fails { #expect(model.message?.contains("保存失败") == true) }
    }
    @Test func leavingDuringUncooperativeVerificationCannotWrite() async throws {
        let q = try quote();
        let store = TestCart([.init(quote: q, quantity: 1)]), verifier = TestVerifier([q])
        let model = CartViewModel(store: store, verifier: verifier)
        let task = Task { await model.observe() }
        await waitUntil { model.checks[1] != nil }
        await verifier.suspend(); model.increase(q.id)
        await waitUntil { await verifier.gate != nil }
        model.stop(); task.cancel(); await verifier.release()
        #expect(model.processingItem == nil)
        await Task.yield()
        #expect(await store.writes == 0); #expect(model.confirmation == nil); #expect(!model.busy)
    }
}
private actor TestCart: ShoppingCart {
    nonisolated let scope = CartScope(environment: "test", accountID: nil)
    var value: ShoppingCartSnapshot
    var subscribers: [AsyncStream<ShoppingCartSnapshot>.Continuation] = []
    var writes = 0
    var failWrites = false
    var holdWrite = false
    var writeGate: CheckedContinuation<Void, Never>?
    var decreaseCalls = 0
    var finishedDecreases = 0
    func suspendWrite() { holdWrite = true }
    func releaseWrite() { writeGate?.resume(); writeGate = nil }
    init(_ lines: [CartLine]) {
        value = .init(scope: .init(environment: "test", accountID: nil), revision: 0, lines: lines)
    }
    func current() -> ShoppingCartSnapshot { value }
    func observe() -> AsyncStream<ShoppingCartSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: ShoppingCartSnapshot.self)
        subscribers.append(continuation); continuation.yield(value); return stream
    }
    func fail() { failWrites = true }
    func publish(_ lines: [CartLine]) {
        value = .init(scope: value.scope, revision: value.revision + 1, lines: lines)
        for s in subscribers { s.yield(value) }
    }
    func add(quantity: Int64, quote: CartQuote, confirmedPrice: CartMoney?, operationID: UUID)
        throws
    {
        try Task.checkCancellation()
        if failWrites { throw ShoppingCartFailure.writeFailed }
        writes += 1
        var lines = value.lines
        if let i = lines.firstIndex(where: { $0.id == quote.id }) {
            lines[i] = .init(quote: quote, quantity: lines[i].quantity + quantity)
        } else {
            lines.append(.init(quote: quote, quantity: quantity))
        }
        publish(lines)
    }
    func increase(
        _ item: CartItemID, quote: CartQuote, confirmedPrice: CartMoney?, expectedRevision: UInt64
    ) throws {
        guard expectedRevision == value.revision else { throw ShoppingCartFailure.staleRevision }
        try Task.checkCancellation()
        if failWrites { throw ShoppingCartFailure.writeFailed }
        let lines = value.lines.map {
            $0.id == item ? CartLine(quote: quote, quantity: $0.quantity + 1) : $0
        }
        writes += 1; publish(lines)
    }
    func decrease(_ item: CartItemID, expectedRevision: UInt64) async throws {
        decreaseCalls += 1
        defer { finishedDecreases += 1 }
        if holdWrite {
            holdWrite = false
            await withCheckedContinuation { writeGate = $0 }
        }
        try Task.checkCancellation()
        if failWrites { throw ShoppingCartFailure.writeFailed }
        writes += 1;
        publish(value.lines.map { $0.id == item ? $0.withQuantity($0.quantity - 1) : $0 })
    }
    func remove(_ items: Set<CartItemID>, expectedRevision: UInt64) throws {
        try Task.checkCancellation()
        if failWrites { throw ShoppingCartFailure.writeFailed }
        writes += 1; publish(value.lines.filter { !items.contains($0.id) })
    }
}
private actor TestVerifier: CartProductChecking {
    var checkValue: CartProductCheck
    var failure = false
    var gate: CheckedContinuation<CartProductCheck, Never>?
    var shouldWait = false
    var calls = 0
    var gateValue: CartProductCheck?
    var released = false
    init(_ quotes: [CartQuote]) {
        checkValue = .init(productID: 1, isAvailable: true, quotes: quotes)
    }
    func replace(_ quotes: [CartQuote], available: Bool = true) {
        checkValue = .init(productID: 1, isAvailable: available, quotes: quotes); failure = false
    }
    func fail() { failure = true }
    func suspend() { shouldWait = true }
    func release() {
        gate?.resume(returning: gateValue ?? checkValue); gate = nil; released = true
    }
    func check(productID: Int64) async throws -> CartProductCheck {
        calls += 1
        if failure { throw ProductDetailLoadFailure.networkUnavailable }
        if shouldWait {
            shouldWait = false; gateValue = checkValue
            return await withCheckedContinuation { gate = $0 }
        }
        return checkValue
    }
}
private func quote(_ spec: Int64 = 1, price: Decimal = 100, stock: Int64 = 10) throws -> CartQuote {
    .init(
        productID: 1, specificationID: spec, title: "手机", specification: "规格\(spec)", imageURL: nil,
        price: try CartMoney(yuan: price), stock: stock)
}
@MainActor private func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async {
    for _ in 0..<2000 { if await condition() { return }; await Task.yield() }
    Issue.record("Expected state not reached")
}
