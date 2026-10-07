import CartFeature
import MallCore
import MallDesignSystem
import SwiftUI

/// App injects a narrow read capability and handles the cross-feature navigation intent.
@MainActor
public struct CatalogEntryView: View {
    @State private var viewModel: CatalogFixtureViewModel
    private let openCart: () -> Void
    public init(products: any ProductLoading, openCart: @escaping () -> Void) {
        _viewModel = State(initialValue: CatalogFixtureViewModel(products: products))
        self.openCart = openCart
    }
    public var body: some View {
        VStack(spacing: 20) {
            FixtureNoticeView(title: "商品入口", detail: "F0 本地夹具 · 尚未接入商品业务")
            switch viewModel.state {
            case .idle, .loading: ProgressView()
            case .ready(let product): Text(product.title).accessibilityIdentifier("catalog.fixture")
            case .failed: Text("夹具加载失败").accessibilityIdentifier("catalog.error")
            }
            Button("打开购物车", action: openCart).accessibilityIdentifier("catalog.openCart")
        }
        .navigationTitle("商品")
        .task { await viewModel.load() }
    }
}
