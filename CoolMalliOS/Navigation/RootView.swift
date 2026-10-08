import CartFeature
import CatalogFeature
import MallDesignSystem
import SwiftUI

@MainActor
struct RootView: View {
    let dependencies: AppDependencies
    @State private var router = SceneRouter()
    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.homePath) {
                CatalogEntryView(products: dependencies.products, openCart: router.openCart)
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        switch route {
                        case .cart:
                            // The independent cart covers the tab bar (Android reference
                            // behavior), so re-tapping the current tab cannot pop it
                            // (PRD-013/NAV-R02; iOS 18+ auto-pops on tab re-tap).
                            CartEntryView(cart: dependencies.cart)
                                .toolbar(.hidden, for: .tabBar)
                        }
                    }
            }
            .tabItem { Label("首页", systemImage: "house") }
            .tag(SceneRouter.Tab.home)
            NavigationStack {
                PendingTabView(
                    marker: "category.pending",
                    title: "分类",
                    detail: "分类页面待接入 · 本入口为导航占位"
                )
            }
            .tabItem { Label("分类", systemImage: "square.grid.2x2") }
            .tag(SceneRouter.Tab.category)
            NavigationStack { CartEntryView(cart: dependencies.cart) }
                .tabItem { Label("购物车", systemImage: "cart") }
                .tag(SceneRouter.Tab.cart)
            NavigationStack {
                PendingTabView(
                    marker: "me.pending",
                    title: "我的",
                    detail: "个人中心待接入 · 本入口为导航占位"
                )
            }
            .tabItem { Label("我的", systemImage: "person") }
            .tag(SceneRouter.Tab.me)
        }
    }
}

/// NAV-01 shell only: the tab targets no business screen yet; pending cards own no state.
private struct PendingTabView: View {
    let marker: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 20) {
            FixtureNoticeView(title: title, detail: detail)
            Text("待接入").font(.headline).accessibilityIdentifier(marker)
        }
        .navigationTitle(title)
    }
}
