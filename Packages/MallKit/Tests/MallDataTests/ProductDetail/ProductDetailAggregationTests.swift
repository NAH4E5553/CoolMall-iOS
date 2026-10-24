import Foundation
import MallCore
@testable import MallData
import Testing

struct ProductDetailAggregationTests {
    private func response(coupons: Any = [], reviews: Any = []) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "code": 1000,
            "data": [
                "goodsInfo": [
                    "id": 830001, "title": "商品", "price": 3999, "sold": 306, "status": 1,
                ],
                "coupon": coupons, "comment": reviews,
            ],
        ])
    }
    private var coupon: [String: Any] {
        [
            "id": 860001, "title": "精选券", "description": "精选商品可用", "amount": 30.25,
            "condition": ["fullAmount": 299.50], "endTime": "2030-01-01 00:00:00",
        ]
    }
    private var review: [String: Any] {
        [
            "id": 850001, "goodsId": 830001, "content": "真实评价", "starCount": 4,
            "nickName": "用户", "avatarUrl": "https://images.invalid/avatar",
            "pics": ["https://images.invalid/review", "http://unsafe.invalid/image"],
        ]
    }
    @Test func mapsExactCouponAmountsRulesAndOrderedReviews() throws {
        var second = review; second["id"] = 850002
        let detail = try ProductDetailDecoder.detail(
            response(coupons: [coupon], reviews: [review, second]), productID: 830001)
        let value = try #require(detail.coupons.first)
        #expect(value.id == 860001); #expect(value.title == "精选券")
        #expect(value.description == "精选商品可用")
        #expect(value.amountYuan == Decimal(string: "30.25"))
        #expect(value.minimumSpendYuan == Decimal(string: "299.50"))
        #expect(value.endTime == "2030-01-01 00:00:00")
        #expect(detail.reviews.map(\.id) == [850001, 850002])
        #expect(detail.reviews[0].productID == detail.id)
        #expect(detail.reviews[0].content == "真实评价")
        #expect(detail.reviews[0].nickname == "用户")
        #expect(detail.reviews[0].starCount == 4)
        #expect(detail.reviews[0].imageURLs.count == 1)
        #expect(detail.reviews[0].avatarURL?.absoluteString == "https://images.invalid/avatar")
    }
    @Test func stringConditionIsDecodedWithoutGuessingThreshold() throws {
        var value = coupon; value["condition"] = #"{"fullAmount":1999}"#
        let detail = try ProductDetailDecoder.detail(response(coupons: [value]), productID: 830001)
        #expect(detail.coupons.first?.minimumSpendYuan == 1999)
        value.removeValue(forKey: "condition")
        #expect(
            try ProductDetailDecoder.detail(response(coupons: [value]), productID: 830001).coupons
                .first?.minimumSpendYuan == nil)
    }
    @Test func nullAndMissingAggregatesAreEmptyNotInvented() throws {
        let detail = try ProductDetailDecoder.detail(
            response(coupons: NSNull(), reviews: NSNull()), productID: 830001)
        #expect(detail.coupons.isEmpty); #expect(detail.reviews.isEmpty)
        let missing = try ProductDetailDecoder.detail(
            ProductDetailServiceTests.fixture("product-detail-valid"), productID: 830001)
        #expect(missing.coupons.isEmpty); #expect(missing.reviews.isEmpty)
    }
    @Test(arguments: [
        "duplicate-coupon", "negative-amount", "negative-threshold", "bad-condition",
        "wrong-review-product", "duplicate-review", "bad-stars", "bad-array",
    ])
    func malformedSuppliedAggregatesFailRatherThanSilentlyDisappear(_ mode: String) throws {
        var value = coupon; var entry = review
        var coupons: Any = [value]; var reviews: Any = [entry]
        switch mode {
        case "duplicate-coupon": coupons = [value, value]
        case "negative-amount": value["amount"] = -1; coupons = [value]
        case "negative-threshold": value["condition"] = ["fullAmount": -1]; coupons = [value]
        case "bad-condition": value["condition"] = "bad JSON"; coupons = [value]
        case "wrong-review-product": entry["goodsId"] = 830002; reviews = [entry]
        case "duplicate-review": reviews = [entry, entry]
        case "bad-stars": entry["starCount"] = 6; reviews = [entry]
        default: reviews = "not an array"
        }
        #expect(throws: ProductDetailLoadFailure.invalidResponse) {
            try ProductDetailDecoder.detail(
                response(coupons: coupons, reviews: reviews), productID: 830001)
        }
    }
}
