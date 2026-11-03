import Foundation
import MallCore
import Testing

struct CheckoutEstimateTests {
    private func coupon(amount: Decimal = 30, minimum: Decimal? = 299) -> UserCoupon {
        UserCoupon(
            id: 1, title: "券", description: "", amountYuan: amount, minimumSpendYuan: minimum,
            startTime: "2020-01-01T00:00:00Z", endTime: "2030-01-01T00:00:00Z", type: 0, status: 1,
            useStatus: 0)
    }
    @Test func exactThresholdDiscountAndClearSelection() throws {
        #expect(try CheckoutEstimate(subtotalYuan: 5499, coupon: coupon()).totalYuan == 5469)
        #expect(try CheckoutEstimate(subtotalYuan: 299, coupon: coupon()).discountYuan == 30)
        #expect(try CheckoutEstimate(subtotalYuan: 299, coupon: nil).totalYuan == 299)
        #expect(throws: OrderWriteFailure.invalidInput) {
            try CheckoutEstimate(subtotalYuan: 298, coupon: coupon())
        }
        #expect(throws: OrderWriteFailure.invalidInput) {
            try CheckoutEstimate(subtotalYuan: 299, coupon: coupon(minimum: nil))
        }
    }
    @Test func discountCannotGoBelowZeroAndExpiredCouponCannotSubmit() throws {
        #expect(try CheckoutEstimate(subtotalYuan: 299, coupon: coupon(amount: 500)).totalYuan == 0)
        #expect(
            try CheckoutEstimate(subtotalYuan: 299, coupon: coupon(amount: 500)).discountYuan == 299
        )
        #expect(throws: OrderWriteFailure.invalidInput) {
            try CheckoutEstimate(
                subtotalYuan: 999, coupon: coupon(), now: Date(timeIntervalSince1970: 2000000000))
        }
        #expect(throws: ShoppingCartFailure.invalidMoney) {
            try OrderAmounts(subtotalYuan: 1, discountYuan: 2)
        }
    }
    @Test func sparseConfirmationCandidatesDoNotChangeOwnedCouponValidation() throws {
        let candidate = UserCoupon(
            id: 7, title: "候选", description: "", amountYuan: 30, minimumSpendYuan: 299,
            startTime: nil, endTime: nil, type: nil, status: nil, useStatus: nil,
            availabilityContext: .checkoutCandidate)
        #expect(candidate.availability() == .available)
        #expect(try CheckoutEstimate(subtotalYuan: 299, coupon: candidate).totalYuan == 269)
        #expect(throws: OrderWriteFailure.invalidInput) {
            try CheckoutEstimate(subtotalYuan: 298, coupon: candidate)
        }
        let owned = UserCoupon(
            id: 7, title: "候选", description: "", amountYuan: 30, minimumSpendYuan: 299,
            startTime: nil, endTime: nil, type: nil, status: nil, useStatus: nil)
        #expect(owned.availability() == .unverified)
    }
    @Test func candidateExplicitLifecycleEvidenceStillBlocksSelection() {
        func value(
            type: Int? = 0, status: Int? = 1, used: Int? = nil,
            start: String? = nil, end: String? = nil
        ) -> CouponAvailability {
            UserCoupon(
                id: 7, title: "候选", description: "", amountYuan: 30,
                minimumSpendYuan: 299, startTime: start, endTime: end,
                type: type, status: status, useStatus: used,
                availabilityContext: .checkoutCandidate
            ).availability(
                at: Date(timeIntervalSince1970: 1793000000))
        }
        #expect(value(used: 1) == .used)
        #expect(value(used: 2) == .expired)
        #expect(value(status: 0) == .disabled)
        #expect(value(type: 99) == .unverified)
        #expect(value(status: 99) == .unverified)
        #expect(value(used: 99) == .unverified)
        #expect(value(end: "2020-01-01T00:00:00Z") == .expired)
        #expect(value(start: "2030-01-01T00:00:00Z") == .upcoming)
        #expect(value(end: "invalid") == .unverified)
        #expect(value(start: "2030-01-01", end: "2020-01-01") == .unverified)
    }

}
