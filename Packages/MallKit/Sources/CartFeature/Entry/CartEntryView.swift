import MallCore
import MallDesignSystem
import SwiftUI

/// Read-only projection of the App-injected cart owner; never creates a second store.
@MainActor
public struct CartEntryView: View {
    @State private var viewModel: CartFixtureViewModel
    public init(cart: any CartObserving) {
        _viewModel = State(initialValue: CartFixtureViewModel(cart: cart))
    }
    public var body: some View {
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
