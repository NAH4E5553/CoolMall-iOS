import Foundation
import MallCore
import Testing

/// H0 value-contract checks: exact public inputs, Decimal losslessness and
/// Equatable identity for the read-only projections.
struct HomeContractTests {
    @Test func snapshotInitializerKeepsSectionOrderAndValues() {
        let banner = HomeBanner(
            id: 810_001, description: "焦点图", imageURL: URL(string: "https://cdn.example.com/a.jpg"))
        let category = HomeCategory(id: 800_001, name: "手机", parentID: nil, imageURL: nil)
        let product = HomeProductSummary(
            id: 830_001, title: "小米", subtitle: "旗舰", imageURL: nil, priceYuan: Decimal(3999))
        let coupon = HomeCouponSummary(id: 860_001, title: "满减券")

        let snapshot = HomeSnapshot(
            banners: [banner],
            categories: [category],
            allCategories: [
                category, HomeCategory(id: 801_001, name: "手机子类", parentID: 800_001, imageURL: nil),
            ],
            featured: [product],
            recommendations: [product],
            goods: [product],
            coupons: [coupon]
        )

        #expect(snapshot.banners.map(\.id) == [810_001])
        #expect(snapshot.allCategories.count == 2)
        #expect(snapshot.allCategories.last?.parentID == 800_001)
        #expect(snapshot.featured.first?.priceYuan == Decimal(3999))
        #expect(snapshot == snapshot)
        #expect(snapshot.coupons == [coupon])
    }

    @Test func integerPriceConvertsToExactYuanDecimal() {
        // Int64 → Decimal is lossless; large response prices stay exact.
        let big = HomeProductSummary(
            id: 1, title: "大额", subtitle: nil, imageURL: nil, priceYuan: Decimal(Int64.max))
        #expect(big.priceYuan == Decimal(Int64.max))
        #expect(big.priceYuan != Decimal(0))

        let zero = HomeProductSummary(
            id: 2, title: "零元", subtitle: nil, imageURL: nil, priceYuan: Decimal(0))
        #expect(zero.priceYuan.isZero)
    }
}
