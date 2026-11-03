import MallCore
import MallDesignSystem
import SwiftUI

/// Read-only projection of the App-injected cart owner; never creates a second store.
@MainActor
struct CartFixtureEntry: View {
    @State private var viewModel: CartFixtureViewModel
    init(cart: any CartObserving) {
        _viewModel = State(initialValue: CartFixtureViewModel(cart: cart))
    }
    var body: some View {
        VStack {
            FixtureNoticeView(title: "购物车入口", detail: "F0 内存夹具 · 尚未接入持久化")
            if let snapshot = viewModel.snapshot {
                Text("夹具条目：\(snapshot.quantities.count)")
                    .accessibilityIdentifier("cart.fixture")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("购物车")
        .task { await viewModel.observe() }
    }
}
