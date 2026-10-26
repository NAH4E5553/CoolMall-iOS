import Foundation
import MallCore
import Testing
@testable import AccountFeature

@MainActor struct CouponReceiveViewModelTests {
    private func settle(_ model: CouponReceiveViewModel) async {
        for _ in 0..<10000 { if !model.busy { return }; await Task.yield() };
        Issue.record("claim did not settle")
    }
    @Test func repeatedReceivedTapPublishesNewToastWithoutAnotherWrite() async throws {
        let receiver = ClaimModelGate();
        let model = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        model.setAccount(1); model.claim(); await receiver.started(1)
        await receiver.resolve(1); await settle(model)
        let first = try #require(model.feedback)
        #expect(first.message == "已领取")
        model.claim()
        #expect(model.feedback?.message == "已领取" && model.feedback?.id != first.id)
        #expect(await receiver.accounts == [1])
    }
    @Test func serverMessageTakesPriorityWithoutTurningRejectionIntoReceipt() async throws {
        let receiver = ClaimModelGate()
        let model = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        model.setAccount(1); model.claim(); await receiver.started(1)
        await receiver.resolve(1, failure: .rejectedMessage(500, "已领取过该优惠券"))
        await settle(model)
        #expect(model.phase == .failed(.rejectedMessage(500, "已领取过该优惠券")))
        #expect(model.feedback?.message == "已领取过该优惠券")
        model.claim(); await receiver.started(2)
        await receiver.resolve(2, message: "优惠券领取成功"); await settle(model)
        #expect(model.phase == .received && model.feedback?.message == "优惠券领取成功")
        let first = try #require(model.feedback)
        model.claim()
        #expect(model.feedback?.message == first.message && model.feedback?.id != first.id)
        #expect(await receiver.accounts == [1, 1])
        model.setAccount(2); model.claim(); await receiver.started(3)
        await receiver.resolve(3, message: " "); await settle(model)
        #expect(model.feedback?.message == "已领取")
    }
    @Test func unknownToastDoesNotInventFailureRollbackOrReplay() async throws {
        let receiver = ClaimModelGate();
        let model = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        model.setAccount(1); model.claim(); await receiver.started(1)
        await receiver.resolve(1, failure: .unconfirmed); await settle(model)
        let first = try #require(model.feedback)
        #expect(first.message == "领取失败，结果未确认，请稍后核对")
        model.claim(); #expect(model.feedback?.id != first.id)
        #expect(model.phase == .unconfirmed && model.feedback?.message == first.message)
        #expect(await receiver.accounts == [1])
    }
    @Test func switchingAccountAndCancellingWaitNeverPublishOldToast() async {
        let receiver = ClaimModelGate();
        let model = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        model.setAccount(1); model.claim(); await receiver.started(1); model.stopWaiting()
        #expect(model.feedback == nil)
        model.setAccount(2); await receiver.resolve(1)
        for _ in 0..<100 { await Task.yield() }
        #expect(model.phase == .idle && model.feedback == nil)
        model.claim(); await receiver.started(2);
        await receiver.resolve(2, failure: .rejected(1701)); await settle(model)
        #expect(model.feedback?.message == "领取失败")
        model.setAccount(nil); #expect(model.feedback == nil)
    }
    @Test func independentCouponsKeepReceiptsWhenAnotherWaitIsStopped() async {
        let receiver = ClaimModelGate()
        let first = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        let second = CouponReceiveViewModel(couponID: 8, receiver: receiver)
        first.setAccount(1); second.setAccount(1)
        first.claim(); await receiver.started(1); second.claim(); await receiver.started(2)
        first.stopWaiting(); await receiver.resolve(2); await settle(second)
        #expect(first.phase == .unconfirmed && second.phase == .received)
        await receiver.resolve(1)
        for _ in 0..<100 { await Task.yield() }
        #expect(first.phase == .unconfirmed && second.phase == .received)
        first.claim(); second.claim(); #expect(await receiver.accounts == [1, 1])
    }
    @Test func guestAndLoginNeverAutoSubmitAndRepeatedTapIsSingleFlight() async {
        let receiver = ClaimModelGate();
        let model = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        model.claim(); #expect(await receiver.accounts.isEmpty)
        model.setAccount(1); model.authenticationCompleted();
        #expect(await receiver.accounts.isEmpty)
        model.claim(); model.claim(); await receiver.started(1)
        #expect(await receiver.accounts == [1]); #expect(model.busy)
        await receiver.resolve(1); await settle(model); #expect(model.phase == .received)
        model.claim(); #expect(await receiver.accounts == [1])
    }
    @Test func stopWaitingRetainsUnknownAndLateOldSuccessCannotClearNewAccountAttempt() async {
        let receiver = ClaimModelGate();
        let model = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        model.setAccount(1); model.claim(); await receiver.started(1); model.stopWaiting()
        #expect(model.phase == .unconfirmed); model.claim(); #expect(await receiver.accounts == [1])
        model.setAccount(2); model.claim(); await receiver.started(2)
        await receiver.resolve(1); await Task.yield(); #expect(model.busy)
        await receiver.resolve(2); await settle(model)
        #expect(model.phase == .received); #expect(await receiver.accounts == [1, 2])
    }
    @Test func authenticationRecoveryAndBusinessRetryRequireExplicitNextTap() async {
        let receiver = ClaimModelGate();
        let model = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        model.setAccount(1); model.claim(); await receiver.started(1)
        await receiver.resolve(1, failure: .authenticationRequired); await settle(model)
        #expect(model.phase == .failed(.authenticationRequired)); model.authenticationCompleted()
        #expect(model.phase == .idle); #expect(await receiver.accounts.count == 1)
        model.claim(); await receiver.started(2);
        await receiver.resolve(2, failure: .rejected(1701)); await settle(model)
        #expect(model.phase == .failed(.rejected(1701)))
        model.claim(); await receiver.started(3); await receiver.resolve(3); await settle(model)
        #expect(model.phase == .received); #expect(await receiver.accounts.count == 3)
    }
    @Test func transportUnknownNeverProvidesAutomaticRetryAndAccountChangeClearsPrivateReceipt()
        async
    {
        let receiver = ClaimModelGate();
        let model = CouponReceiveViewModel(couponID: 7, receiver: receiver)
        model.setAccount(1); model.claim(); await receiver.started(1)
        await receiver.resolve(1, failure: .unconfirmed); await settle(model)
        #expect(model.phase == .unconfirmed); model.claim(); model.authenticationCompleted()
        #expect(await receiver.accounts.count == 1); #expect(model.phase == .unconfirmed)
        model.setAccount(nil); #expect(model.phase == .idle); model.claim();
        #expect(await receiver.accounts.count == 1)
    }
}
private actor ClaimModelGate: CouponReceiving {
    var accounts: [Int64] = []
    private var gates: [Int: CheckedContinuation<String?, any Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func receiveCoupon(accountID: Int64, couponID: Int64) async throws -> String? {
        accounts.append(accountID); let count = accounts.count
        return try await withCheckedThrowingContinuation { c in
            gates[count] = c; let ready = waiters.filter { $0.0 <= count };
            waiters.removeAll { $0.0 <= count }; ready.forEach { $0.1.resume() }
        }
    }
    func started(_ count: Int) async {
        if gates[count] != nil { return };
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func resolve(_ id: Int, failure: CouponClaimFailure? = nil, message: String? = nil) {
        let c = gates.removeValue(forKey: id)
        if let failure { c?.resume(throwing: failure) } else { c?.resume(returning: message) }
    }
}
