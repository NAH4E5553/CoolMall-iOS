import MallCore
import Testing
@testable import AccountFeature

@MainActor struct OrderCountsViewModelTests {
    @MainActor final class Loader: OrderCountsLoading {
        var calls: [Int64] = []
        var hold = false
        var failure = false
        var gate: CheckedContinuation<UserOrderCounts, Error>?
        func loadOrderCounts(accountID: Int64) async throws -> UserOrderCounts {
            calls.append(accountID)
            if hold { hold = false; return try await withCheckedThrowingContinuation { gate = $0 } }
            if failure { throw PageReadFailure.networkUnavailable }
            return try UserOrderCounts(unpaid: 0, unshipped: 101, refunding: 2, refunded: 3)
        }
    }
    func wait(_ loader: Loader) async {
        for _ in 0..<1000 { if loader.gate != nil { return }; await Task.yield() }
        Issue.record("controlled count request missing")
    }
    @Test func guestsInactiveAndUnavailableNeverRead() async {
        let loader = Loader()
        for id: Int64? in [nil, 0, -1] {
            let model = OrderCountsViewModel(accountID: id, loader: loader)
            await model.activate(true); #expect(model.counts == nil); #expect(!model.loading)
        }
        let model = OrderCountsViewModel(accountID: 1, loader: loader)
        await model.activate(false); #expect(loader.calls.isEmpty)
        await model.activate(true); #expect(model.counts?.unpaid == 0)
        #expect(model.counts?.unshipped == 101); #expect(model.counts?.afterSale == 5)
        await model.activate(false); #expect(model.counts == nil)
    }
    @Test func failureHidesOldCountsAndReturningRetries() async {
        let loader = Loader(); let model = OrderCountsViewModel(accountID: 1, loader: loader)
        await model.activate(true); loader.failure = true; await model.activate(true)
        #expect(model.counts == nil); #expect(model.failure == .networkUnavailable)
        loader.failure = false; await model.activate(true)
        #expect(model.failure == nil); #expect(model.counts?.afterSale == 5)
        #expect(loader.calls == [1, 1, 1]); model.stop()
    }
    @Test func replacementRejectsLateSuccessAndFailure() async throws {
        for fail in [false, true] {
            let loader = Loader(); loader.hold = true
            let model = OrderCountsViewModel(accountID: 1, loader: loader)
            let old = Task { await model.activate(true) }; await wait(loader)
            await model.activate(true)
            if fail {
                loader.gate?.resume(throwing: PageReadFailure.timeout)
            } else {
                loader.gate?.resume(returning: try UserOrderCounts(unpaid: 999))
            }
            await old.value
            #expect(model.counts?.unpaid == 0); #expect(model.failure == nil)
            model.stop()
        }
    }
    @Test func leavingAndCancellationRejectUncooperativeReplies() async throws {
        for cancel in [false, true] {
            let loader = Loader(); loader.hold = true
            let model = OrderCountsViewModel(accountID: 1, loader: loader)
            let task = Task { await model.activate(true) }; await wait(loader)
            if cancel { task.cancel() } else { model.stop() }
            loader.gate?.resume(returning: try UserOrderCounts(unpaid: 9)); await task.value
            #expect(model.counts == nil); #expect(model.failure == nil); #expect(!model.loading)
        }
    }
}
