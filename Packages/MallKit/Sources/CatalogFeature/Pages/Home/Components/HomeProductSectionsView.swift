import MallCore
import MallImages
import SwiftUI

struct HomeProductSectionsView: View {
    let snapshot: HomeSnapshot
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 16) {
            if !snapshot.featured.isEmpty {
                HomeSectionView(title: "限时精选", key: "flashSale", action: action) {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(snapshot.featured, id: \.id) { product in
                                card(product, key: "flashSale", horizontal: false)
                                    .frame(width: typeSize.isAccessibilitySize ? 280 : 180)
                            }
                        }
                    }
                }
            }
            if !snapshot.recommendations.isEmpty {
                HomeSectionView(title: "推荐商品", key: "recommend") {
                    VStack(spacing: 12) {
                        ForEach(snapshot.recommendations, id: \.id) { product in
                            card(product, key: "recommend", horizontal: true)
                        }
                    }
                }
            }
            if !snapshot.goods.isEmpty {
                HomeSectionView(title: "全部商品", key: "goods") {
                    if typeSize.isAccessibilitySize {
                        // Measure these finite single-column rows together so
                        // Tab transitions retain the same content height.
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(snapshot.goods, id: \.id) { product in
                                card(product, key: "goods", horizontal: false)
                            }
                        }
                    } else {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 12),
                                count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading,
                            spacing: 12
                        ) {
                            ForEach(snapshot.goods, id: \.id) { product in
                                card(product, key: "goods", horizontal: false)
                            }
                        }
                    }
                }
            }
        }
    }
    private func card(_ product: HomeProductSummary, key: String, horizontal: Bool) -> some View {
        HomeProductCardView(
            product: product, key: key, pipeline: pipeline,
            isActive: isActive, horizontal: horizontal, action: action)
    }
}
