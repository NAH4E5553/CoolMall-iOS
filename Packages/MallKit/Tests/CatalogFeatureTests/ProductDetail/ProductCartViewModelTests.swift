import Foundation
import MallCore
@testable import CatalogFeature
import Testing

@Suite @MainActor struct ProductCartViewModelTests {
    private func specification(_ price: Decimal = 100) -> ProductSpecification {
        .init(id: 1, productID: 1, name: "白", priceYuan: price, stock: 10, imageURLs: [])
    }
    @Test func repeatedTapProducesOneCommittedAddition() async throws {
        let q = try quote(); let store = TestCart([]), verifier = TestVerifier([q])
        await verifier.suspend()
        let model = ProductCartViewModel(store: store, verifier: verifier); model.setActive(true)
        model.add(specification: specification(), quantity: 2)
        model.add(specification: specification(), quantity: 2)
        await waitUntil { await verifier.gate != nil }
        await verifier.release()
        await waitUntil { model.success == 1 }
        #expect(await store.writes == 1);
        #expect(try await store.current().lines.first?.quantity == 2)
    }
    @Test func priceConfirmationCancellationAndSecondChangeNeverWriteOldAuthorization() async throws
    {
        let store = TestCart([]), verifier = TestVerifier([try quote(price: 120)])
        let model = ProductCartViewModel(store: store, verifier: verifier); model.setActive(true)
        model.add(specification: specification(), quantity: 1)
        await waitUntil { model.confirmation != nil }
        model.cancel(); #expect(await store.writes == 0)
        model.add(specification: specification(), quantity: 1)
        await waitUntil { model.confirmation != nil }
        await verifier.replace([try quote(price: 130)]); model.confirmPrice()
        await waitUntil { model.confirmation?.new.cents == 13000 }
        #expect(await store.writes == 0)
        model.confirmPrice(); await waitUntil { model.success == 1 }
        #expect(try await store.current().lines.first?.unitPrice.cents == 13000)
    }
    @Test func priceReturningToInitialValueStillNeedsAnotherConfirmation() async throws {
        let store = TestCart([]), verifier = TestVerifier([try quote(price: 120)])
        let model = ProductCartViewModel(store: store, verifier: verifier); model.setActive(true)
        model.add(specification: specification(), quantity: 1)
        await waitUntil { model.confirmation != nil }
        await verifier.replace([try quote(price: 100)])
        model.confirmPrice()
        await waitUntil { model.confirmation != nil || model.success > 0 }
        #expect(model.confirmation?.new.cents == 10000)
        #expect(await store.writes == 0)
        #expect(model.success == 0)
        model.confirmPrice()
        await waitUntil { model.success == 1 }
        #expect(await store.writes == 1)
        #expect(try await store.current().lines.first?.unitPrice.cents == 10000)
    }
    @Test func knownZeroStockSelectionCannotStartAnAddition() async throws {
        let store = TestCart([]), verifier = TestVerifier([try quote()])
        let model = ProductCartViewModel(store: store, verifier: verifier); model.setActive(true)
        let empty = ProductSpecification(
            id: 1, productID: 1, name: "无货", priceYuan: 100, stock: 0, imageURLs: [])
        model.add(specification: empty, quantity: 1)
        await waitUntil { !model.busy }
        #expect(await verifier.calls == 0); #expect(await store.writes == 0)
        #expect(model.success == 0); #expect(model.confirmation == nil)
    }
    @Test func existingQuantityParticipatesInStockLimit() async throws {
        let q = try quote(stock: 5), store = TestCart([.init(quote: try quote(), quantity: 3)])
        let model = ProductCartViewModel(store: store, verifier: TestVerifier([q]));
        model.setActive(true)
        model.add(specification: specification(), quantity: 3)
        await waitUntil { model.message != nil }
        #expect(await store.writes == 0); #expect(model.success == 0)
    }
    @Test func leavingDuringCheckRejectsLateResultAndDoesNotShowSuccess() async throws {
        let store = TestCart([]), verifier = TestVerifier([try quote()]); await verifier.suspend()
        let model = ProductCartViewModel(store: store, verifier: verifier); model.setActive(true)
        model.add(specification: specification(), quantity: 1)
        await waitUntil { await verifier.gate != nil }
        model.setActive(false); await verifier.release(); await Task.yield()
        #expect(await store.writes == 0); #expect(model.success == 0); #expect(!model.busy)
    }
    @Test func diskFailureDoesNotReportSuccessOrResetDraft() async throws {
        let store = TestCart([]); await store.fail()
        let model = ProductCartViewModel(store: store, verifier: TestVerifier([try quote()]));
        model.setActive(true)
        model.add(specification: specification(), quantity: 3)
        await waitUntil { model.message != nil }
        #expect(model.success == 0); #expect(try await store.current().lines.isEmpty)
    }
}
private actor TestCart: ShoppingCart {
    nonisolated let scope = CartScope(environment: "test", accountID: nil)
    var value: ShoppingCartSnapshot
    var subscribers: [AsyncStream<ShoppingCartSnapshot>.Continuation] = []
    var writes = 0
    var failWrites = false
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
    func decrease(_ item: CartItemID, expectedRevision: UInt64) throws {
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
    init(_ quotes: [CartQuote]) {
        checkValue = .init(productID: 1, isAvailable: true, quotes: quotes)
    }
    func replace(_ quotes: [CartQuote]) {
        checkValue = .init(productID: 1, isAvailable: true, quotes: quotes)
    }
    func fail() { failure = true }
    func suspend() { shouldWait = true }
    func release() { gate?.resume(returning: checkValue); gate = nil }
    func check(productID: Int64) async throws -> CartProductCheck {
        calls += 1
        if failure { throw ProductDetailLoadFailure.networkUnavailable }
        if shouldWait { return await withCheckedContinuation { gate = $0 } }
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
