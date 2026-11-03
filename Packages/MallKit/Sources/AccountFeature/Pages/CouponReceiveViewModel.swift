import Foundation
import MallCore
import Observation

@MainActor @Observable final class CouponReceiveViewModel {
    enum Phase: Equatable {
        case idle, submitting, received, unconfirmed, failed(CouponClaimFailure)
    }
    struct Feedback: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }
    private(set) var feedback: Feedback?
    private let couponID: Int64
    private let receiver: any CouponReceiving
    private var receiptMessage: String?
    private var accountID: Int64?
    private var generation: UInt64 = 0
    @ObservationIgnored private var request: Task<Void, Never>?
    private(set) var phase: Phase = .idle
    var busy: Bool { phase == .submitting }
    init(couponID: Int64, receiver: any CouponReceiving) {
        self.couponID = couponID; self.receiver = receiver
    }
    deinit { request?.cancel() }
    func setAccount(_ value: Int64?) {
        guard value != accountID else { return }
        generation &+= 1; request?.cancel(); request = nil; accountID = value; phase = .idle;
        feedback = nil; receiptMessage = nil
    }
    func authenticationCompleted() {
        if phase == .failed(.authenticationRequired) { phase = .idle }
    }
    func claim() {
        guard let accountID, accountID > 0, request == nil else { return }
        switch phase {
        case .received, .unconfirmed: publishFeedback(); return
        case .idle, .failed: break
        case .submitting: return
        }
        generation &+= 1; let epoch = generation; phase = .submitting
        let receiver = receiver; let couponID = couponID
        request = Task { @MainActor [weak self] in
            let result: Phase
            var message: String?
            do {
                try Task.checkCancellation()
                message = try await receiver.receiveCoupon(accountID: accountID, couponID: couponID)
                try Task.checkCancellation(); result = .received
            } catch is CancellationError { result = .unconfirmed } catch let failure
                as CouponClaimFailure
            {
                result =
                    failure == .unconfirmed || failure == .busy ? .unconfirmed : .failed(failure)
            } catch { result = .unconfirmed }
            guard let self, self.generation == epoch else { return }
            self.request = nil; self.phase = result;
            self.receiptMessage = result == .received ? message : nil;
            self.publishFeedback()
        }
    }
    private func publishFeedback() {
        let message: String
        switch phase {
        case .received: message = displayMessage(receiptMessage) ?? "已领取"
        case .unconfirmed: message = "领取失败，结果未确认，请稍后核对"
        case .failed(.authenticationRequired): message = "领取失败，请重新登录"
        case .failed(.rejectedMessage(_, let value)): message = displayMessage(value) ?? "领取失败"
        case .failed: message = "领取失败"
        default: return
        }
        feedback = Feedback(message: message)
    }
    private func displayMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    func stopWaiting() {
        guard busy else { return }
        generation &+= 1; request?.cancel(); request = nil; phase = .unconfirmed
    }
}
