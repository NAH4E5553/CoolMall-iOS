import Foundation
import MallCore
import Observation

/// One page owns mutable selections; navigation carries only the immutable purchase input.
@MainActor @Observable final class CheckoutViewModel {
    let intent: BuyNowIntent
    private let accountID: Int64
    private let loader: any CheckoutLoading
    private let now: () -> Date
    private var active = false
    private var needsRead = true
    private var generation: UInt64 = 0
    private var selectionGeneration: UInt64 = 0
    private var choseAddress = false
    private(set) var address: ShippingAddress?
    private(set) var coupons: [UserCoupon]?
    private(set) var selectedCoupon: UserCoupon?
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var failure: PageReadFailure?
    private(set) var attempt = 0
    private(set) var notice: String?
    init(
        accountID: Int64, intent: BuyNowIntent, loader: any CheckoutLoading,
        now: @escaping () -> Date = Date.init
    ) {
        self.accountID = accountID; self.intent = intent; self.loader = loader; self.now = now
    }
    func activate(_ value: Bool) async {
        active = value
        guard value else { stop(); return }
        if needsRead && failure == nil { await refresh() }
    }
    func refresh() async {
        guard active, !loading, !Task.isCancelled else { return }
        generation &+= 1; let epoch = generation; loading = true; failure = nil
        defer { if epoch == generation { loading = false } }
        do {
            let context = try await loader.loadCheckout(accountID: accountID)
            try Task.checkCancellation()
            guard active, epoch == generation else { return }
            if !choseAddress { address = context.defaultAddress }
            coupons = context.coupons; loaded = true; needsRead = false
            if let selectedCoupon,
                context.coupons?.first(where: { $0.id == selectedCoupon.id }) != selectedCoupon
                    || selectedCoupon.availability(at: now()) != .available
            {
                self.selectedCoupon = nil; notice = "优惠券信息已变化，请重新选择"
            }
        } catch {
            guard active, epoch == generation, !Task.isCancelled, !(error is CancellationError)
            else { return }
            needsRead = true; failure = (error as? PageReadFailure) ?? .invalidResponse
        }
    }
    func retry() { needsRead = true; failure = nil; attempt += 1 }
    func chooseCoupon(_ coupon: UserCoupon?) {
        guard active else { return }
        if let coupon {
            guard coupons?.contains(coupon) == true, coupon.availability(at: now()) == .available
            else {
                return
            }
        }
        selectedCoupon = coupon; notice = nil
    }
    func addressSelection() -> @MainActor (ShippingAddress) -> Void {
        selectionGeneration &+= 1; let epoch = selectionGeneration
        return { [weak self] address in
            guard let self, self.active, self.selectionGeneration == epoch, address.id > 0 else {
                return
            }
            self.address = address; self.choseAddress = true
        }
    }
    func stop() {
        active = false; generation &+= 1; selectionGeneration &+= 1; loading = false
    }
}
