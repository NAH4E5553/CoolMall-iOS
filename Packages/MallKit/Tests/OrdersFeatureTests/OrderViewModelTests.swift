import Foundation
import MallCore
import Testing
@testable import OrdersFeature

@MainActor struct OrderViewModelTests {
    static func order(_ id: Int64 = 7, status: Int = 0) -> OrderSnapshot {
        OrderSnapshot(
            id: id, number: nil, status: status, title: nil, createdAt: nil,
            paidAt: nil, address: nil, lines: nil)
    }
    @MainActor final class Loader: OrdersLoading {
        var calls: [(OrderFilter, Int)] = []
        var holdList = false
        var holdDetail = false
        var failAppend = false
        var failRefresh = false
        var wrongDetail = false
        var listGate: CheckedContinuation<NumberedPage<OrderSnapshot>, Error>?
        var detailGate: CheckedContinuation<OrderSnapshot, Error>?
        func loadOrders(accountID: Int64, filter: OrderFilter, page: Int, pageSize: Int)
            async throws -> NumberedPage<OrderSnapshot>
        {
            calls.append((filter, page))
            if holdList {
                holdList = false; return try await withCheckedThrowingContinuation { listGate = $0 }
            }
            if page == 2 && failAppend { failAppend = false; throw PageReadFailure.timeout }
            if page == 1 && failRefresh {
                failRefresh = false; throw PageReadFailure.networkUnavailable
            }
            let count = page == 1 ? 10 : 1
            return NumberedPage(
                items: (0..<count).map {
                    Self.row(Int64((page - 1) * 10 + $0 + 1), filter: filter)
                }, page: page, size: pageSize, total: 11)
        }
        static func row(_ id: Int64, filter: OrderFilter) -> OrderSnapshot {
            OrderViewModelTests.order(id, status: filter.wireStatuses?.first ?? 0)
        }
        func loadOrder(accountID: Int64, orderID: Int64) async throws -> OrderSnapshot {
            if holdDetail { return try await withCheckedThrowingContinuation { detailGate = $0 } }
            return OrderViewModelTests.order(wrongDetail ? orderID + 1 : orderID)
        }
    }
    func wait(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        Issue.record("controlled operation did not arrive")
    }
    @Test func filterSwitchRejectsLateResultAndStartsAtFirstPage() async {
        let loader = Loader(); loader.holdList = true
        let model = OrderListViewModel(accountID: 1, filter: .all, loader: loader)
        let first = Task { await model.activate(true) }; await wait { loader.listGate != nil }
        model.select(.unevaluated); #expect(model.state.items.isEmpty)
        await model.activate(true)
        loader.listGate?.resume(
            returning: NumberedPage(items: [Self.order(99)], page: 1, size: 10, total: 1))
        await first.value
        #expect(model.filter == .unevaluated); #expect(model.state.items.count == 10)
        #expect(model.state.items.allSatisfy { $0.status == 3 }); #expect(loader.calls.last?.1 == 1)
        model.stop()
    }
    @Test func failedAppendRetriesSamePageAndRefreshFailureRetainsCommittedRows() async {
        let loader = Loader(); loader.failAppend = true
        let model = OrderListViewModel(accountID: 1, filter: .all, loader: loader)
        await model.activate(true); model.more(); await wait { model.state.appendFailure != nil }
        #expect(model.state.items.count == 10); #expect(model.state.nextPage == 2)
        model.more(); await wait { model.state.items.count == 11 }
        #expect(loader.calls.suffix(2).map { $0.1 } == [2, 2]); #expect(model.state.nextPage == nil)
        loader.failRefresh = true; await model.refresh()
        #expect(model.state.items.count == 11); #expect(model.state.failure == .networkUnavailable)
        model.stop()
    }
    @Test func detailRejectsWrongIdentityAndCanRetry() async {
        let loader = Loader(); loader.wrongDetail = true
        let model = OrderDetailViewModel(accountID: 1, orderID: 7, loader: loader)
        await model.activate(true); #expect(model.order == nil);
        #expect(model.failure == .invalidResponse)
        loader.wrongDetail = false; model.retry(); await model.activate(true)
        #expect(model.order?.id == 7); #expect(model.failure == nil); model.stop()
    }
    @Test func leavingRejectsUncooperativeLateDetail() async {
        let loader = Loader(); loader.holdDetail = true
        let model = OrderDetailViewModel(accountID: 1, orderID: 7, loader: loader)
        let task = Task { await model.activate(true) }; await wait { loader.detailGate != nil }
        model.stop(); loader.detailGate?.resume(returning: Self.order()); await task.value
        #expect(model.order == nil); #expect(model.failure == nil); #expect(!model.loading)
    }
    @Test func duplicateInitialActivationDoesNotDuplicateReads() async {
        let loader = Loader(); loader.holdDetail = true
        let model = OrderDetailViewModel(accountID: 1, orderID: 7, loader: loader)
        let task = Task { await model.activate(true) }; await wait { loader.detailGate != nil }
        await model.activate(true); loader.detailGate?.resume(returning: Self.order());
        await task.value
        #expect(model.order?.id == 7); model.stop()
    }
}
