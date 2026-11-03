import MallCore
import MallImages
import SwiftUI

struct HomeProductSectionsView: View {
    let snapshot: HomeSnapshot
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let action: () -> Void
    var onOpenProduct: ((Int64) -> Void)? = nil
    var onShowFeatured: (() -> Void)? = nil
    var goodsModel: HomeGoodsViewModel? = nil
    var viewport = CGRect.zero
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var featuredWidth = 120.0
    var body: some View {
        VStack(spacing: 16) {
            if !snapshot.featured.isEmpty {
                HomeSectionView(title: "限时精选", key: "flashSale", action: onShowFeatured ?? action) {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(snapshot.featured, id: \.id) { product in
                                card(product, key: "flashSale", role: .featured)
                                    .frame(
                                        width: typeSize.isAccessibilitySize
                                            ? min(featuredWidth, 320) : 120)
                            }
                        }
                    }
                    .accessibilityIdentifier("home.flashSale.items")
                }
                .padding(12)
                .background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if !snapshot.recommendations.isEmpty {
                HomeSectionView(title: "推荐商品", key: "recommend") {
                    VStack(spacing: 12) {
                        ForEach(snapshot.recommendations, id: \.id) { product in
                            card(product, key: "recommend", role: .recommendation)
                        }
                    }
                }
            }
            if !goods.isEmpty || goodsModel != nil {
                HomeSectionView(title: "全部商品", key: "goods") {
                    if typeSize.isAccessibilitySize {
                        // Measure these finite single-column rows together so
                        // Tab transitions retain the same content height.
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(goods, id: \.id) { product in
                                card(product, key: "goods", role: .goods)
                            }
                        }
                    } else {
                        HomeWaterfallLayout {
                            ForEach(goods, id: \.id) { product in
                                card(product, key: "goods", role: .goods)
                            }
                        }
                    }
                    if let goodsModel { goodsFooter(goodsModel) }
                }
            }
        }
    }
    private var surface: Color { colorScheme == .dark ? Color(white: 0.12) : .white }
    private var goods: [HomeProductSummary] {
        goodsModel?.products(fallback: snapshot.goods) ?? snapshot.goods
    }

    @ViewBuilder private func goodsFooter(_ model: HomeGoodsViewModel) -> some View {
        if !model.state.hasLoaded || model.state.nextPage != nil {
            VStack(spacing: 8) {
                if model.state.failure != nil || model.state.appendFailure != nil {
                    Text("加载失败，请重试").font(.footnote).foregroundStyle(.secondary)
                }
                if model.state.operation != nil { ProgressView() }
                if model.state.failure != nil || model.state.appendFailure != nil {
                    Button("重试加载") { model.loadMore() }
                        .disabled(!isActive || model.state.operation != nil)
                        .accessibilityIdentifier("home.goods.retry")
                }
            }.frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.goods.tail")
                // VStack eagerly creates children; onAppear alone is not proof of reaching the tail.
                .onGeometryChange(for: Bool.self) { geometry in
                    isActive && viewport.height > 0
                        && geometry.frame(in: .global).intersects(viewport)
                } action: {
                    model.tailVisibilityChanged($0)
                }
                .onDisappear { model.tailVisibilityChanged(false) }
        } else {
            Text(goods.isEmpty ? "暂无商品" : "没有更多商品了")
                .font(.footnote).foregroundStyle(.secondary).padding()
                .accessibilityIdentifier("home.goods.end")
        }
    }

    private func card(_ product: HomeProductSummary, key: String, role: HomeProductCardView.Role)
        -> some View
    {
        HomeProductCardView(
            product: product, key: key, pipeline: pipeline,
            isActive: isActive, role: role,
            action: {
                if let onOpenProduct { onOpenProduct(product.id) } else { action() }
            })
    }
}

/// Loaded home cards are measured together, preserving source order
/// and stable content height across Tab transitions. Each next item uses the
/// shortest column; the first pair starts on the same top edge.
private struct HomeWaterfallLayout: Layout {
    private let spacing = 12.0
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        return CGSize(width: width, height: positions(width: width, subviews: subviews).height)
    }
    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = positions(width: bounds.width, subviews: subviews)
        let width = (bounds.width - spacing) / 2
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
        }
    }
    private func positions(width: CGFloat, subviews: Subviews) -> (
        points: [CGPoint], height: CGFloat
    ) {
        let columnWidth = max(0, (width - spacing) / 2)
        var heights: [CGFloat] = [0, 0]
        var points: [CGPoint] = []
        for subview in subviews {
            let column = heights[0] <= heights[1] ? 0 : 1
            points.append(CGPoint(x: CGFloat(column) * (columnWidth + spacing), y: heights[column]))
            heights[column] +=
                subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
                + spacing
        }
        return (points, max(0, (heights.max() ?? 0) - spacing))
    }
}
