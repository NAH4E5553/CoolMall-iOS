import MallCore
import MallImages
import SwiftUI

@MainActor
struct ProductSpecificationSheet: View {
    let model: ProductDetailViewModel
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let maxContentHeight: CGFloat
    let dismiss: () -> Void
    var onAdd: () -> Void = {}
    var onBuy: () -> Void = {}
    var isAdding = false
    @ScaledMetric private var titleSize = 16.0
    @ScaledMetric private var summarySize = 12.0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var topHeight: CGFloat = 130
    @State private var bottomHeight: CGFloat = 104
    @State private var choicesHeight: CGFloat = 150
    private struct ReadKey: Equatable { let active: Bool; let attempt: Int }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                Text("选择规格").font(.system(size: titleSize, weight: .bold)).frame(
                    maxWidth: .infinity
                )
                .accessibilityIdentifier("detail.spec.title")
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20).onEnded { value in
                        if value.translation.height > 60 { dismiss() }
                    })
                header
                Divider()
                HStack {
                    ProductDetailSectionTitle(title: "规格分类")
                    Button {
                        model.toggleLayout()
                    } label: {
                        Image(
                            systemName: model.isGrid ? "list.bullet.rectangle" : "square.grid.3x3"
                        )
                        .font(.title3).foregroundStyle(
                            ProductDetailStyle.onSurface(scheme).opacity(0.6))
                    }
                    .accessibilityLabel(model.isGrid ? "切换列表" : "切换网格")
                    .accessibilityIdentifier("detail.spec.layout")
                    .buttonStyle(.plain)
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                topHeight = $0
            }
            ScrollView {
                specificationContent.disabled(isAdding)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        choicesHeight = $0
                    }
            }
            .frame(
                height: min(
                    choicesHeight,
                    max(44, maxContentHeight + titleSize + 20 - topHeight - bottomHeight - 56))
            )
            .accessibilityIdentifier("detail.spec.scroll")
            VStack(spacing: 12) {
                quantity.disabled(isAdding)
                ProductDetailPurchaseButtons(
                    onAdd: onAdd, onBuy: onBuy, isAdding: isAdding,
                    addIdentifier: "detail.spec.addCart", canAdd: model.canAddToCart)
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                bottomHeight = $0
            }
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(ProductDetailStyle.surface(scheme)).ignoresSafeArea(edges: .bottom)
        }
        .foregroundStyle(ProductDetailStyle.onSurface(scheme))
        .accessibilityAction(.escape, dismiss)
        .task(id: ReadKey(active: isActive, attempt: model.specificationAttempt)) {
            guard !Task.isCancelled else { return }
            guard isActive else { model.closeSpecifications(); return }
            await model.loadSpecifications()
        }
        .onDisappear { model.closeSpecifications() }
    }

    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            // Give the price the whole available line at accessibility sizes;
            // a fixed thumbnail must not force the amount into an ellipsis.
            VStack(alignment: .leading, spacing: 12) {
                price
                HStack(alignment: .top, spacing: 12) {
                    thumbnail
                    selectionSummary
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 8) {
                    price
                    selectionSummary
                }
            }
        }
    }

    private var thumbnail: some View {
        ProductSpecificationImage(
            url: model.selected?.imageURLs.first ?? model.detail?.imageURLs.first,
            pipeline: pipeline, isActive: isActive
        )
        .frame(width: 100, height: 100).accessibilityHidden(true)
    }

    private var price: some View {
        ProductDetailPriceView(amount: model.selected?.priceYuan ?? model.detail?.priceYuan ?? 0)
            .accessibilityIdentifier("detail.spec.price")
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.selected.map { "已选：" + $0.name } ?? "请选择规格")
                .font(.system(size: summarySize)).foregroundStyle(
                    ProductDetailStyle.secondary(scheme)
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("detail.spec.selection")
            if let selected = model.selected {
                Text(verbatim: "库存：\(selected.stock)")
                    .font(.system(size: summarySize)).foregroundStyle(
                        ProductDetailStyle.tertiary(scheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detail.spec.stock")
            }
        }
    }

    @ViewBuilder
    private var specificationContent: some View {
        switch model.specificationState {
        case .idle, .loading:
            ProgressView("正在加载规格").padding(24).frame(maxWidth: .infinity)
                .accessibilityIdentifier("detail.spec.loading")
        case .failed(let failure):
            VStack(spacing: 12) {
                Text("规格加载失败").accessibilityIdentifier("detail.spec.error")
                Text(detailFailureDescription(failure)).foregroundStyle(.secondary)
                Button("重试规格") { model.retrySpecifications() }
                    .accessibilityIdentifier("detail.spec.retry")
            }.padding(.vertical, 24).frame(maxWidth: .infinity)
        case .empty:
            VStack(spacing: 12) {
                Text("暂无规格").accessibilityIdentifier("detail.spec.empty")
                Button("重新读取") { model.retrySpecifications() }
                    .accessibilityIdentifier("detail.spec.retry")
            }.padding(.vertical, 24).frame(maxWidth: .infinity)
        case .ready(let specifications):
            if model.isGrid && !typeSize.isAccessibilitySize {
                // Finite source list, measured for natural-height shrinkage.
                ProductSpecificationGrid {
                    ForEach(specifications) { specification in option(specification, grid: true) }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(specifications) { specification in option(specification, grid: false) }
                }
            }
        }
    }

    private func option(_ specification: ProductSpecification, grid: Bool) -> some View {
        let selected = model.selectedID == specification.id
        return Button {
            model.select(specification.id)
        } label: {
            ProductSpecificationOption(
                specification: specification, selected: selected, grid: grid,
                imageURL: specification.imageURLs.first ?? model.detail?.imageURLs.first,
                pipeline: pipeline, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("detail.spec.\(specification.id)")
    }

    private var quantity: some View {
        HStack {
            ProductDetailSectionTitle(title: "数量")
            Spacer()
            Button {
                model.changeQuantity(by: -1)
            } label: {
                Image(systemName: "minus").foregroundStyle(.secondary)
                    .frame(width: 24, height: 24).background(.secondary.opacity(0.06), in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44).accessibilityLabel("减少数量")
            .disabled(model.selected == nil || model.quantity <= 1 || model.selected?.stock == 0)
            .accessibilityIdentifier("detail.spec.minus")
            Text(verbatim: "\(model.quantity)").monospacedDigit()
                .accessibilityIdentifier("detail.spec.quantity")
            Button {
                model.changeQuantity(by: 1)
            } label: {
                Image(systemName: "plus").foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(
                        ProductDetailStyle.accent, in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44).accessibilityLabel("增加数量")
            .disabled(model.selected == nil || model.quantity >= (model.selected?.stock ?? 0))
            .accessibilityIdentifier("detail.spec.plus")
        }
    }
}

private struct ProductSpecificationOption: View {
    let specification: ProductSpecification
    let selected: Bool
    let grid: Bool
    let imageURL: URL?
    let pipeline: MallImagePipeline?
    let isActive: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if grid {
                VStack(alignment: .center, spacing: 0) {
                    ProductSpecificationImage(url: imageURL, pipeline: pipeline, isActive: isActive)
                        .aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
                    labels
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ProductSpecificationImage(url: imageURL, pipeline: pipeline, isActive: isActive)
                        .frame(width: 64, height: 64).accessibilityHidden(true)
                    labels
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected ? ProductDetailStyle.accent.opacity(0.05) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    selected
                        ? ProductDetailStyle.accent
                        : ProductDetailStyle.border(scheme).opacity(0.8),
                    lineWidth: 1)
        }
    }
    private var labels: some View {
        Text(specification.name).font(.caption)
            .foregroundStyle(
                selected ? ProductDetailStyle.accent : ProductDetailStyle.onSurface(scheme)
            )
            .multilineTextAlignment(grid ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: grid ? .center : .leading)
            .padding(8)
    }

}

private struct ProductSpecificationImage: View {
    let url: URL?
    let pipeline: MallImagePipeline?
    let isActive: Bool
    var body: some View {
        GeometryReader { proxy in
            if let pipeline {
                RemoteImage(
                    url: url, targetSize: proxy.size,
                    contentMode: .fit, pipeline: pipeline, isEnabled: isActive)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
    }
}

/// Three equal columns, measured together so the surrounding ScrollView can
/// shrink for a short list and scroll only when the content cap is reached.
private struct ProductSpecificationGrid: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? 320)
        return CGSize(
            width: width,
            height: rows(width, subviews).reduce(0, +)
                + CGFloat(max(0, (subviews.count + 2) / 3 - 1)) * 12)
    }
    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let heights = rows(bounds.width, subviews)
        let width = max(0, (bounds.width - 24) / 3)
        var y = bounds.minY
        for row in heights.indices {
            for column in 0..<3 {
                let index = row * 3 + column
                guard index < subviews.count else { continue }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (width + 12), y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: heights[row]))
            }
            y += heights[row] + 12
        }
    }
    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [CGFloat] {
        let columnWidth = max(0, (width - 24) / 3)
        var heights = [CGFloat](repeating: 0, count: (subviews.count + 2) / 3)
        for (index, view) in subviews.enumerated() {
            heights[index / 3] = max(
                heights[index / 3],
                view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height)
        }
        return heights
    }
}
