import MallCore
import MallDesignSystem
import SwiftUI

/// App injects a narrow read capability and handles the cross-feature navigation intents.
@MainActor
public struct CatalogEntryView: View {
    @State private var viewModel: CatalogFixtureViewModel
    private let openCart: () -> Void
    private let openProduct: (Int64) -> Void
    public init(
        products: any ProductLoading,
        openCart: @escaping () -> Void,
        openProduct: @escaping (Int64) -> Void
    ) {
        _viewModel = State(initialValue: CatalogFixtureViewModel(products: products))
        self.openCart = openCart
        self.openProduct = openProduct
    }
    public var body: some View {
        VStack(spacing: 20) {
            FixtureNoticeView(title: "首页（工程夹具）", detail: "真实首页待接入 · 当前展示本地工程夹具")
            switch viewModel.state {
            case .idle, .loading: ProgressView()
            case .ready(let product):
                Text(product.title).accessibilityIdentifier("catalog.fixture")
                // NAV-03: the fixture emits a typed goodsId intent; the App owns routing.
                Button("打开商品详情") { openProduct(product.id) }
                    .accessibilityIdentifier("catalog.openProduct")
            case .failed: Text("夹具加载失败").accessibilityIdentifier("catalog.error")
            }
            Button("打开购物车", action: openCart).accessibilityIdentifier("catalog.openCart")
        }
        .navigationTitle("首页")
        .task { await viewModel.load() }
    }
}
