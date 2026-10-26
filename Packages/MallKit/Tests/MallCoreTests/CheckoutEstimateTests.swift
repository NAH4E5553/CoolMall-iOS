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
}
