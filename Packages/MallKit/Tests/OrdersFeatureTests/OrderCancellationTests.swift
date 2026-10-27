import Foundation
import MallCore
import Testing
@testable import OrdersFeature

@MainActor struct OrderCancellationTests {
    @MainActor final class Service: OrdersLoading, OrderCancelling {
        var status = 0
        var failRead = false
        var error: OrderWriteFailure?
        var holdNextRead = false
        var readGate: CheckedContinuation<OrderSnapshot, Error>?
        var readCalls = 0
        var reasonAuthFailure = false
        var holdReasons = false
        var holdCancel = false
        var reasonGate: CheckedContinuation<[OrderCancelReason], Error>?
        var cancelGate: CheckedContinuation<Void, Error>?
        var writes = 0
        func loadOrders(accountID: Int64, filter: OrderFilter, page: Int, pageSize: Int)
            async throws -> NumberedPage<OrderSnapshot>
        {
            NumberedPage(items: [], page: page, size: pageSize, total: 0)
        }
        func loadOrder(accountID: Int64, orderID: Int64) async throws -> OrderSnapshot {
            readCalls += 1
            if holdNextRead {
                holdNextRead = false;
                return try await withCheckedThrowingContinuation { readGate = $0 }
            }
            if failRead { throw PageReadFailure.timeout }
            return OrderViewModelTests.order(orderID, status: status)
        }
        func loadCancelReasons(accountID: Int64) async throws -> [OrderCancelReason] {
            if reasonAuthFailure { throw PageReadFailure.authenticationRequired }
            if holdReasons { return try await withCheckedThrowingContinuation { reasonGate = $0 } }
            return [.init(id: 1, name: "后端原因")]
        }
        func cancelOrder(accountID: Int64, orderID: Int64, reason: OrderCancelReason) async throws {
            writes += 1
            if holdCancel { return try await withCheckedThrowingContinuation { cancelGate = $0 } }
            if let error { throw error }
        }
    }
    func wait(_ predicate: () -> Bool) async {
        for _ in 0..<1000 { if predicate() { return }; await Task.yield() };
        Issue.record("controlled gate absent")
    }
    @Test func acknowledgementRequiresAuthoritativeClosedReadAndReadFailureNeverFabricatesStatus()
        async
    {
        let service = Service()
        let detail = OrderDetailViewModel(
            accountID: 1, orderID: 7, loader: service, canceller: service)
        await detail.activate(true); await detail.loadReasons(); service.failRead = true
        #expect(await detail.cancel()); #expect(detail.order?.status == 0);
        #expect(detail.cancelLocked)
        #expect(detail.failure == .timeout); #expect(!detail.canCancel)
        service.failRead = false; service.status = 7; await detail.refresh()
        #expect(detail.order?.status == 7); #expect(!detail.canCancel); #expect(service.writes == 1)
    }
    @Test func refreshWhileReasonsAreLoadingDoesNotStrandSpinnerOrIgnoreReasons() async {
        let service = Service(); service.holdReasons = true
        let model = OrderDetailViewModel(
            accountID: 1, orderID: 7, loader: service, canceller: service)
        await model.activate(true)
        let task = Task { await model.loadReasons() }; await wait { service.reasonGate != nil }
        await model.refresh()
        service.reasonGate?.resume(returning: [.init(id: 3, name: "真实原因")]); await task.value
        #expect(!model.reasonsLoading); #expect(model.selectedReason?.id == 3)
    }
    @Test func refreshDuringCancelKeepsWriteSingleFlightAndClosesAfterTrueRead() async {
        let service = Service(); service.holdCancel = true
        let model = OrderDetailViewModel(
            accountID: 1, orderID: 7, loader: service, canceller: service)
        await model.activate(true); await model.loadReasons()
        let task = Task { await model.cancel() }; await wait { service.cancelGate != nil }
        await model.refresh(); #expect(!(await model.cancel())); #expect(service.writes == 1)
        service.status = 7; service.cancelGate?.resume(); #expect(await task.value)
        #expect(model.order?.status == 7); #expect(!model.cancelling)
    }
    @Test func cancellationAcknowledgementSupersedesOldReadAndAlwaysStartsPostWriteRead() async {
        let service = Service()
        let model = OrderDetailViewModel(
            accountID: 1, orderID: 7, loader: service, canceller: service)
        await model.activate(true); await model.loadReasons()
        service.holdNextRead = true
        let old = Task { await model.refresh() }; await wait { service.readGate != nil }
        service.status = 7
        #expect(await model.cancel()); #expect(model.order?.status == 7);
        #expect(service.readCalls == 3)
        service.readGate?.resume(returning: OrderViewModelTests.order(7, status: 0));
        await old.value
        #expect(model.order?.status == 7); #expect(!model.loading)
    }
    @Test func unknownCancelLocksButDefiniteBusinessRejectionCanRetryAndLeavingRejectsLateResult()
        async
    {
        let service = Service()
        let detail = OrderDetailViewModel(
            accountID: 1, orderID: 7, loader: service, canceller: service)
        await detail.activate(true); await detail.loadReasons()
        service.error = .rejected(code: 500, message: "订单已变化")
        #expect(!(await detail.cancel())); #expect(detail.canCancel)
        #expect(detail.cancelFailure?.message == "订单已变化")
        service.error = .unconfirmed; #expect(!(await detail.cancel())); #expect(!detail.canCancel)
        #expect(detail.order?.status == 0); #expect(service.writes == 2)
        let second = Service(); second.holdCancel = true
        let other = OrderDetailViewModel(
            accountID: 1, orderID: 7, loader: second, canceller: second)
        await other.activate(true); await other.loadReasons()
        let task = Task { await other.cancel() }; await wait { second.cancelGate != nil }
        other.stop(); second.status = 7; second.cancelGate?.resume()
        #expect(!(await task.value)); #expect(other.order?.status == 0)
    }
    @Test func reasonReadAuthenticationFailureRemainsLoginRecoverable() async {
        let service = Service(); service.reasonAuthFailure = true
        let model = OrderDetailViewModel(
            accountID: 1, orderID: 7, loader: service, canceller: service)
        await model.activate(true); await model.loadReasons()
        #expect(model.cancelFailure == .authenticationRequired); #expect(model.reasons == nil)
        service.reasonAuthFailure = false; await model.loadReasons()
        #expect(model.selectedReason?.id == 1); #expect(model.cancelFailure == nil)
    }

}
