import MallCore
import MallImages
import SwiftUI

/// Six source-ordered sections, each hidden with its own empty array.
struct HomeContentView: View {
    let snapshot: HomeSnapshot
    var imagePipeline: MallImagePipeline? = nil
    var isActive = true
    @Environment(\.colorScheme) private var colorScheme
    var onUnavailableAction: () -> Void = {}
    var body: some View {
        VStack(spacing: 16) {
            if !snapshot.banners.isEmpty {
                HomeBannerCarouselView(
                    banners: snapshot.banners, imagePipeline: imagePipeline, isActive: isActive,
                    onUnavailableAction: onUnavailableAction
                )
            }
            if !snapshot.coupons.isEmpty {
                HomeCouponSectionView(coupons: snapshot.coupons, action: onUnavailableAction)
                    .background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if !snapshot.categories.isEmpty {
                HomeCategorySectionView(
                    categories: snapshot.categories, pipeline: imagePipeline, isActive: isActive,
                    action: onUnavailableAction
                )
                .padding(.vertical, 12)
                .background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            HomeProductSectionsView(
                snapshot: snapshot, pipeline: imagePipeline, isActive: isActive,
                action: onUnavailableAction)
        }
    }
    private var surface: Color { colorScheme == .dark ? Color(white: 0.12) : .white }
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
