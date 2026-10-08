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
                        destination(for: route)
                    }
            }
            .tabItem { Label("首页", systemImage: "house") }
            .tag(SceneRouter.Tab.home)
            NavigationStack(path: $router.categoryPath) {
                PendingTabView(
                    marker: "category.pending",
                    title: "分类",
                    detail: "分类页面待接入 · 本入口为导航占位",
                    pushProbe: { router.categoryPath.append(.fixturePathProbe(label: "category")) }
                )
                .navigationDestination(for: SceneRouter.Route.self) { route in
                    destination(for: route)
                }
            }
            .tabItem { Label("分类", systemImage: "square.grid.2x2") }
            .tag(SceneRouter.Tab.category)
            NavigationStack(path: $router.cartPath) {
                CartEntryView(cart: dependencies.cart)
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem { Label("购物车", systemImage: "cart") }
            .tag(SceneRouter.Tab.cart)
            NavigationStack(path: $router.mePath) {
                PendingTabView(
                    marker: "me.pending",
                    title: "我的",
                    detail: "个人中心待接入 · 本入口为导航占位",
                    pushProbe: { router.mePath.append(.fixturePathProbe(label: "me")) }
                )
                .navigationDestination(for: SceneRouter.Route.self) { route in
                    destination(for: route)
                }
            }
            .tabItem { Label("我的", systemImage: "person") }
            .tag(SceneRouter.Tab.me)
        }
    }

    /// Pushed routes cover the tab bar (the PRD-016 pattern from NAV-01), so
    /// re-tapping the current tab stays reachable only at tab roots, where the
    /// system pop-to-root is a no-op (PRD-013/NAV-R02; iOS 18+ auto-pops on
    /// tab re-tap and that cannot be vetoed with public API).
    @ViewBuilder
    private func destination(for route: SceneRouter.Route) -> some View {
        switch route {
        case .cart:
            CartEntryView(cart: dependencies.cart)
                .toolbar(.hidden, for: .tabBar)
        case .fixturePathProbe(let label):
            FixturePathProbeView(label: label)
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

/// NAV-01 shell placeholders. NAV-02 adds a fixture-only path probe so per-tab
/// path behavior stays observable until real screens arrive; still no business state.
private struct PendingTabView: View {
    let marker: String
    let title: String
    let detail: String
    let pushProbe: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            FixtureNoticeView(title: title, detail: detail)
            Text("待接入").font(.headline).accessibilityIdentifier(marker)
            Button("压入路径自检页", action: pushProbe)
                .accessibilityIdentifier("\(marker).pushProbe")
        }
        .navigationTitle(title)
    }
}

/// NAV-02 engineering fixture: makes per-tab path push/pop and page identity
/// observable before any real screen exists. No requests, no persistence, no
/// business semantics; superseded when NAV-03 adds real typed routes.
private struct FixturePathProbeView: View {
    let label: String
    @State private var identityTicks = 0
    var body: some View {
        VStack(spacing: 20) {
            FixtureNoticeView(
                title: "路径自检（工程夹具）",
                detail: "真实页面待接入 · 仅验证每 Tab 独立路径与页面身份"
            )
            Text("身份计数：\(identityTicks)")
                .accessibilityIdentifier("\(label).probeIdentity")
            Button("身份计数 +1") { identityTicks += 1 }
                .accessibilityIdentifier("\(label).probeTick")
        }
        .navigationTitle("路径自检")
    }
}
