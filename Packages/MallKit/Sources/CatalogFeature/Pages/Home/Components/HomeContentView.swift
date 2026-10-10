import MallCore
import SwiftUI

/// HOME-02 content container: composes the six PRD-015 section skeletons from
/// a single read-only `HomeSnapshot`. A section appears only when its OWN
/// array is non-empty, in the fixed order 轮播 → 优惠券 → 分类 → 限时精选 →
/// 推荐商品 → 全部商品; an empty section hides together with its title,
/// placeholder and reserved area. Pure display: no service, no view model,
/// no second writable copy of data, no filtering/sorting of the source arrays.
/// `allCategories` stays auxiliary and never becomes a seventh business
/// section.
struct HomeContentView: View {
    private enum Section: CaseIterable {
        case banner
        case coupon
        case category
        case flashSale
        case recommend
        case goods

        var title: String {
            switch self {
            case .banner: "轮播"
            case .coupon: "优惠券"
            case .category: "分类"
            case .flashSale: "限时精选"
            case .recommend: "推荐商品"
            case .goods: "全部商品"
            }
        }

        /// Engineering placeholder for this card only; real content belongs
        /// to HOME-04—HOME-10 cards.
        var pendingText: String { "\(title)内容待接入" }

        var accessibilityKey: String {
            switch self {
            case .banner: "banner"
            case .coupon: "coupon"
            case .category: "category"
            case .flashSale: "flashSale"
            case .recommend: "recommend"
            case .goods: "goods"
            }
        }

        func isVisible(in snapshot: HomeSnapshot) -> Bool {
            switch self {
            case .banner: !snapshot.banners.isEmpty
            case .coupon: !snapshot.coupons.isEmpty
            case .category: !snapshot.categories.isEmpty
            case .flashSale: !snapshot.featured.isEmpty
            case .recommend: !snapshot.recommendations.isEmpty
            case .goods: !snapshot.goods.isEmpty
            }
        }
    }

    private let snapshot: HomeSnapshot

    init(snapshot: HomeSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        // Non-lazy on purpose: all six skeletons are cheap placeholders, and
        // eager composition keeps empty-section hiding structural.
        VStack(spacing: 16) {
            ForEach(Section.allCases.filter { $0.isVisible(in: snapshot) }, id: \.self) { section in
                HomeSectionView(
                    title: section.title,
                    pendingText: section.pendingText,
                    titleAccessibilityID: "home.section.\(section.accessibilityKey).title",
                    pendingAccessibilityID: "home.section.\(section.accessibilityKey).pending"
                )
            }
        }
    }
}

#if DEBUG
    private extension HomeSnapshot {
        /// Preview-only synthetic data; mirrors no production fixture file.
        static func preview(
            banners: Int = 1,
            coupons: Int = 1,
            categories: Int = 1,
            featured: Int = 1,
            recommendations: Int = 1,
            goods: Int = 1,
            allCategories: Int = 3
        ) -> HomeSnapshot {
            HomeSnapshot(
                banners: (0..<banners).map {
                    HomeBanner(id: Int64(900_100 + $0), description: "预览轮播", imageURL: nil)
                },
                categories: (0..<categories).map {
                    HomeCategory(
                        id: Int64(900_200 + $0), name: "预览分类", parentID: nil, imageURL: nil)
                },
                allCategories: (0..<allCategories).map {
                    HomeCategory(
                        id: Int64(900_300 + $0), name: "预览完整分类", parentID: nil, imageURL: nil)
                },
                featured: (0..<featured).map {
                    HomeProductSummary(
                        id: Int64(900_400 + $0), title: "预览精选商品", subtitle: nil,
                        imageURL: nil, priceYuan: Decimal(1))
                },
                recommendations: (0..<recommendations).map {
                    HomeProductSummary(
                        id: Int64(900_500 + $0),
                        title: $0 == 0 ? "预览推荐短标题" : "预览推荐长标题——验证特大字体换行与左对齐",
                        subtitle: nil, imageURL: nil, priceYuan: Decimal(2))
                },
                goods: (0..<goods).map {
                    HomeProductSummary(
                        id: Int64(900_600 + $0), title: "预览全部商品", subtitle: nil,
                        imageURL: nil, priceYuan: Decimal(3))
                },
                coupons: (0..<coupons).map {
                    HomeCouponSummary(id: Int64(900_700 + $0), title: "预览优惠券")
                }
            )
        }
    }

    #Preview("六区（valid 形态）") {
        ScrollView {
            HomeContentView(snapshot: .preview())
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
        }
    }

    #Preview("部分空（layout-mixed 形态）") {
        ScrollView {
            HomeContentView(snapshot: .preview(banners: 0, categories: 0))
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
        }
    }

    #Preview("仅辅助分类 + 特大字体") {
        ScrollView {
            HomeContentView(
                snapshot: .preview(
                    banners: 0, coupons: 0, categories: 0, featured: 0, recommendations: 0, goods: 0
                )
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .dynamicTypeSize(.accessibility5)
    }

    #Preview("深色") {
        ScrollView {
            HomeContentView(snapshot: .preview())
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
        }
        .preferredColorScheme(.dark)
    }
#endif
