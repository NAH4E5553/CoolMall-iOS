import Foundation
import MallCore
import Testing
@testable import CheckoutFeature

@MainActor struct CheckoutViewModelTests {
    static func intent() throws -> BuyNowIntent {
        try BuyNowIntent(
            product: ProductDetailSnapshot(
                id: 9, title: "商品", subtitle: nil, priceYuan: 999,
                sold: 0, isAvailable: true, imageURLs: [], contentImageURLs: []),
            specification: ProductSpecification(
                id: 4, productID: 9, name: "规格", priceYuan: 999, stock: 3, imageURLs: []),
            quantity: 2)
    }
    static func address(_ id: Int64) -> ShippingAddress {
        ShippingAddress(id: id, value: ShippingAddressInput(contact: "联系人\(id)"))
    }
    static func coupon(_ id: Int64) -> UserCoupon {
        UserCoupon(
            id: id, title: "券", description: "候选", amountYuan: 30, minimumSpendYuan: 299,
            startTime: "2020-01-01T00:00:00Z", endTime: "2030-01-01T00:00:00Z", type: 0, status: 1,
            useStatus: 0)
    }
    @MainActor final class Loader: CheckoutLoading {
        var hold = false
        var fail = false
        var calls = 0
        var context = CheckoutContext(defaultAddress: address(1), coupons: [coupon(1)])
        var gate: CheckedContinuation<CheckoutContext, Error>?
        func loadCheckout(accountID: Int64) async throws -> CheckoutContext {
            calls += 1
            if hold { hold = false; return try await withCheckedThrowingContinuation { gate = $0 } }
            if fail { throw PageReadFailure.timeout }; return context
        }
    }
    func wait(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() };
        Issue.record("gate did not arrive")
    }
    @Test func subtotalStaysUnchangedWhenCouponSelectedAndRefreshPreservesAddress() async throws {
        let loader = Loader();
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        await model.activate(true); model.chooseCoupon(Self.coupon(1));
        model.addressSelection()(Self.address(7))
        await model.refresh()
        #expect(model.address?.id == 7); #expect(model.selectedCoupon?.id == 1)
        #expect(model.intent.subtotalYuan == 1998); #expect(model.loaded); model.stop()
    }
    @Test func lateDefaultDoesNotOverwriteUserSelectionAndOldCallbackCannotChangeNewVisit()
        async throws
    {
        let loader = Loader(); loader.hold = true
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        let task = Task { await model.activate(true) }; await wait { loader.gate != nil }
        let old = model.addressSelection(); old(Self.address(7))
        loader.gate?.resume(returning: loader.context); await task.value
        #expect(model.address?.id == 7)
        model.stop(); await model.activate(true); old(Self.address(8));
        #expect(model.address?.id == 7)
        model.addressSelection()(Self.address(9)); #expect(model.address?.id == 9); model.stop()
    }
    @Test func changedOrMissingCouponIsClearedWithoutInventedDeduction() async throws {
        let loader = Loader();
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        await model.activate(true); model.chooseCoupon(Self.coupon(1))
        loader.context = CheckoutContext(defaultAddress: nil, coupons: nil); await model.refresh()
        #expect(model.selectedCoupon == nil); #expect(model.coupons == nil);
        #expect(model.notice != nil)
        #expect(model.intent.subtotalYuan == 1998); model.stop()
    }
    @MainActor final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }
    @Test func unchangedCouponCrossingExpiryIsClearedOnlyAfterSuccessfulRefresh() async throws {
        let end = try #require(ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z"))
        let clock = Clock(end.addingTimeInterval(-1)); let loader = Loader()
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, now: { clock.date })
        await model.activate(true); model.chooseCoupon(Self.coupon(1)); await model.refresh()
        #expect(model.selectedCoupon?.id == 1)
        clock.date = end; loader.fail = true; await model.refresh()
        #expect(model.selectedCoupon?.id == 1); #expect(model.failure == .timeout)
        loader.fail = false; await model.refresh()
        #expect(model.selectedCoupon == nil); #expect(model.notice != nil)
        #expect(model.intent.subtotalYuan == 1998)
        model.chooseCoupon(Self.coupon(1)); #expect(model.selectedCoupon == nil); model.stop()
    }
    @Test func refreshFailurePreservesSelectionsAndRetryIsExplicit() async throws {
        let loader = Loader();
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        await model.activate(true); model.chooseCoupon(Self.coupon(1)); loader.fail = true
        await model.refresh(); #expect(model.failure == .timeout); #expect(model.address?.id == 1)
        #expect(model.selectedCoupon?.id == 1); #expect(loader.calls == 2)
        loader.fail = false; model.retry(); await model.activate(true)
        // Loaded contexts refresh through the explicit retry action, not an automatic replay.
        #expect(model.failure == nil); #expect(loader.calls == 3); model.stop()
    }
    @Test func leavingRejectsLateContextAndInvalidCouponCannotBeSelected() async throws {
        let loader = Loader(); loader.hold = true
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        let task = Task { await model.activate(true) }; await wait { loader.gate != nil }
        model.stop(); loader.gate?.resume(returning: loader.context); await task.value
        #expect(!model.loaded); #expect(model.address == nil)
        await model.activate(true); model.chooseCoupon(Self.coupon(2));
        #expect(model.selectedCoupon == nil)
        model.stop()
    }
    @MainActor final class Creator: OrderCreating {
        var calls = 0
        var known: Int64?
        func knownCreatedOrder(accountID: Int64, intentID: UUID) async throws -> Int64? { known }
        var error: OrderWriteFailure?
        var hold = false
        var gate: CheckedContinuation<Int64, Error>?
        func createOrder(accountID: Int64, input: OrderCreation) async throws -> Int64 {
            calls += 1
            if hold { return try await withCheckedThrowingContinuation { gate = $0 } }
            if let error { throw error }; return 71
        }
    }
    @Test func createOwnsSelectionsAndDoubleClickCannotSendTwice() async throws {
        let loader = Loader(), creator = Creator(); creator.hold = true
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, creator: creator)
        await model.activate(true); model.chooseCoupon(Self.coupon(1))
        #expect(model.estimate?.totalYuan == 1968)
        let task = Task { await model.submit() }; await wait { creator.gate != nil }
        #expect(await model.submit() == nil); #expect(creator.calls == 1)
        model.chooseCoupon(nil); #expect(model.selectedCoupon?.id == 1)
        creator.gate?.resume(returning: 71); #expect(await task.value == 71)
        #expect(!model.canSubmit); #expect(model.writeLocked)
    }
    @Test func unknownCreateLocksWhileRejectedMessageRemainsRetryableAndLateSuccessCannotNavigate()
        async throws
    {
        let loader = Loader(), creator = Creator()
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, creator: creator)
        await model.activate(true); creator.error = .rejected(code: 500, message: "库存不足")
        #expect(await model.submit() == nil); #expect(model.canSubmit)
        #expect(model.writeFailure?.message == "库存不足")
        creator.error = .unconfirmed; #expect(await model.submit() == nil);
        #expect(!model.canSubmit)
        let late = Creator(); late.hold = true
        let other = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, creator: late)
        await other.activate(true)
        let task = Task { await other.submit() }; await wait { late.gate != nil }
        other.stop(); late.gate?.resume(returning: 71); #expect(await task.value == nil)
    }

    @Test func establishedOrderRestoresBeforeUnavailableContextOrCouponValidation() async throws {
        let loader = Loader(); loader.fail = true
        let creator = Creator(); creator.known = 71
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, creator: creator)
        await model.activate(true)
        #expect(model.recoveredOrderID == 71); #expect(model.writeLocked)
        #expect(loader.calls == 0); #expect(creator.calls == 0)
    }

    @Test func couponExpiringDuringWriteCannotMutateSubmittedSelectionOnRepeatedTap() async throws {
        let end = try #require(ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z"))
        let clock = Clock(end.addingTimeInterval(-1)), loader = Loader(), creator = Creator()
        creator.hold = true
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader,
            now: { clock.date }, creator: creator)
        await model.activate(true); model.chooseCoupon(Self.coupon(1))
        let task = Task { await model.submit() }; await wait { creator.gate != nil }
        clock.date = end
        #expect(await model.submit() == nil); #expect(creator.calls == 1)
        #expect(model.selectedCoupon?.id == 1); #expect(model.writeFailure == nil)
        creator.gate?.resume(returning: 71); #expect(await task.value == 71)
    }

}
