import MallCore
import MallImages
import SwiftUI

/// Product-bound paged reviews. App owns the navigation stack and injects read-only dependencies.
@MainActor
public struct ProductReviewsEntryView: View {
    private let productID: Int64
    private let loader: any ProductReviewsLoading
    private let imagePipeline: MallImagePipeline?
    private let isActive: Bool
    public init(
        productID: Int64, loader: any ProductReviewsLoading,
        imagePipeline: MallImagePipeline? = nil, isActive: Bool
    ) {
        self.productID = productID; self.loader = loader
        self.imagePipeline = imagePipeline; self.isActive = isActive
    }
    public var body: some View {
        ProductReviewsScreen(
            productID: productID, loader: loader, pipeline: imagePipeline, isActive: isActive
        )
        .id(productID)
    }
}

@MainActor
private struct ProductReviewsScreen: View {
    @State private var model: ProductReviewsViewModel
    @State private var viewport: CGRect = .zero
    @State private var footerFrame: CGRect = .zero
    @State private var requestedBack = false
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric private var titleSize = 16.0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    let pipeline: MallImagePipeline?
    let isActive: Bool
    init(
        productID: Int64, loader: any ProductReviewsLoading, pipeline: MallImagePipeline?,
        isActive: Bool
    ) {
        _model = State(initialValue: ProductReviewsViewModel(productID: productID, loader: loader))
        self.pipeline = pipeline; self.isActive = isActive
    }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("正在加载评价").accessibilityIdentifier("reviews.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let failure):
                VStack(spacing: 12) {
                    Text("评价加载失败").accessibilityIdentifier("reviews.error")
                    Text(detailFailureDescription(failure)).foregroundStyle(
                        ProductDetailStyle.secondary(scheme))
                    Button("重试") { Task { await model.retryInitial() } }.accessibilityIdentifier(
                        "reviews.retry")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                list
            }
        }
        .foregroundStyle(ProductDetailStyle.onSurface(scheme))
        .background(ProductDetailStyle.background(scheme))
        .navigationTitle("商品评价").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("商品评价").font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(ProductDetailStyle.onSurface(scheme))
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { backButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { backButton }
            }
        }
        .toolbarBackground(ProductDetailStyle.surface(scheme), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(ProductDetailStyle.onSurface(scheme))
        .task(id: active) {
            model.setActive(active)
            if active { await model.loadInitial() }
        }
        .onChange(of: active) { _, value in model.setActive(value) }
        .onChange(of: tailIsVisible) { _, visible in
            if visible { model.tailAppeared() } else { model.tailDisappeared() }
        }
        .onDisappear { model.setActive(false) }
        .overlay(alignment: .leading) {
            Color.clear.frame(width: 20).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20).onEnded { value in
                        if value.translation.width > 80,
                            abs(value.translation.height) < value.translation.width / 2
                        {
                            goBack()
                        }
                    }
                ).accessibilityHidden(true)
        }
    }
    private var backButton: some View {
        Button(action: goBack) {
            Image("detail-back", bundle: .module).resizable().frame(width: 24, height: 24)
                .foregroundStyle(ProductDetailStyle.onSurface(scheme))
                .frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("返回")
            .accessibilityIdentifier("reviews.back")
    }
    private func goBack() {
        guard isActive, !requestedBack else { return }
        requestedBack = true; dismiss()
    }
    private var list: some View {
        List {
            if model.items.isEmpty {
                Text("暂无评价").frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityIdentifier("reviews.empty").reviewRow()
            }
            ForEach(model.items) { review in
                ProductReviewCard(
                    review: review, createdAt: review.createdAt, pipeline: pipeline,
                    isActive: active
                )
                .reviewRow()
            }
            if let failure = model.refreshFailure {
                Text("刷新失败，已保留原评价：" + detailFailureDescription(failure))
                    .font(.footnote).foregroundStyle(ProductDetailStyle.secondary(scheme))
                    .accessibilityIdentifier("reviews.refresh.error").reviewRow()
            }
            footer.reviewRow()
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .contentMargins(.top, 12, for: .scrollContent)
        .onGeometryChange(for: CGRect.self) { geometry in
            let frame = geometry.frame(in: .global); let inset = geometry.safeAreaInsets
            return CGRect(
                x: frame.minX + inset.leading, y: frame.minY + inset.top,
                width: max(0, frame.width - inset.leading - inset.trailing),
                height: max(0, frame.height - inset.top - inset.bottom))
        } action: {
            viewport = $0
        }
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("reviews.list")
        .accessibilityValue(Text(verbatim: "商品ID：\(model.productID)"))
    }
    private var tailIsVisible: Bool {
        !viewport.isEmpty && !footerFrame.isEmpty && viewport.intersects(footerFrame)
    }
    private var footer: some View {
        VStack(spacing: 8) {
            if model.operation == .append {
                ProgressView("加载中…").accessibilityIdentifier("reviews.more.loading")
            } else if model.appendFailure != nil {
                Button("加载失败，点击重试") { model.loadMore() }.accessibilityIdentifier(
                    "reviews.more.retry")
            } else if model.nextPage != nil {
                Button("加载更多") { model.loadMore() }.accessibilityIdentifier("reviews.more")
            } else {
                Text("没有更多了").font(.footnote).foregroundStyle(ProductDetailStyle.tertiary(scheme))
                    .accessibilityIdentifier("reviews.exhausted")
            }
        }.frame(maxWidth: .infinity, minHeight: 44)
            // Both geometry inputs may arrive in either order on first layout.
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                footerFrame = $0
            }
            .onDisappear {
                footerFrame = .zero; model.tailDisappeared()
            }
    }
}
private extension View {
    func reviewRow() -> some View {
        listRowSeparator(.hidden).listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12))
    }
}
