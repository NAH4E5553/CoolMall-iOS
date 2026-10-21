import CartFeature
import CatalogFeature
import Foundation
import MallDesignSystem
import SwiftUI

@MainActor
struct RootView: View {
    let dependencies: AppDependencies
    @State private var router = SceneRouter()
    #if DEBUG
        @Environment(\.scenePhase) private var bannerAuditScenePhase
    #endif
    @State private var unavailableNotice: UUID?
    @State private var categoryUnavailableNotice: UUID?
    @State private var categoryRequestedChildID: Int64?
    #if DEBUG
        private let navTestControl: NavigationTestControl
    #endif

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        #if DEBUG
            let control = NavigationTestControl()
            navTestControl = control
            let seededRouter = SceneRouter()
            control.seed(into: seededRouter)
            _router = State(initialValue: seededRouter)
        #endif
    }

    var body: some View {
        tabs
            #if DEBUG
                .onChange(of: bannerAuditScenePhase, initial: true) { _, phase in
                    router.recordBannerSceneInput(isActive: phase == .active)
                }
                // R-NAV-02-AT05-01: the control strip reserves layout space at the
                // bottom instead of floating over the top, so it can never cover
                // the navigation title/back area at any content size.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if navTestControl.isEnabled {
                        NavigationTestControlOverlay(router: router)
                    }
                }
            #endif
    }

    private var tabs: some View {
        // HOME-02-R1 (DEC-010): TabView selection writes go through the App
        // entry so a re-tap of the selected home tab (an equal-value write,
        // phase-A-verified) bumps the read-only event the home entry
        // consumes; programmatic switches keep writing `selectedTab` directly.
        TabView(
            selection: Binding(
                get: { router.selectedTab },
                set: { router.selectFromTabBar($0) }
            )
        ) {
            NavigationStack(path: $router.homePath) {
                homeRoot
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        destination(for: route, on: .home)
                    }
            }
            .tabItem { Label("首页", systemImage: "house") }
            .tag(SceneRouter.Tab.home)
            NavigationStack(path: $router.categoryPath) {
                categoryRoot
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        destination(for: route, on: .category)
                    }
            }
            .tabItem { Label("分类", systemImage: "square.grid.2x2") }
            .tag(SceneRouter.Tab.category)
            NavigationStack(path: $router.cartPath) {
                CartEntryView(cart: dependencies.cart)
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        destination(for: route, on: .cart)
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
                    destination(for: route, on: .me)
                }
            }
            .tabItem { Label("我的", systemImage: "person") }
            .tag(SceneRouter.Tab.me)
        }
    }

    /// Home is visible only at its own tab root; pushed routes and other tabs
    /// make the home read inactive (H0 visibility contract).
    private var homeIsVisible: Bool {
        router.selectedTab == .home && router.homePath.isEmpty
    }

    /// Only an explicit DEBUG home-fixture launch may suppress banner playback
    /// for controlled manual chains; Release and normal Debug always allow it.
    private var allowsBannerAutoplay: Bool {
        #if DEBUG
            return
                !(dependencies.homeTesting.fixtureMode != nil
                && ProcessInfo.processInfo.arguments.contains("--ui-banner-manual"))
        #else
            return true
        #endif
    }

    /// Category tab root (CATEGORY-01). Normal Debug/Release show the real
    /// read page; the existing DEBUG navigation-fixture launch keeps the
    /// original engineering placeholder root so NAV-02/03 path/identity
    /// assertions remain unchanged. A present-but-invalid category fixture flag
    /// fails closed to an explicit configuration error.
    @ViewBuilder
    private var categoryRoot: some View {
        #if DEBUG
            if dependencies.categoryTesting.configError {
                CategoryTestConfigErrorView()
            } else if dependencies.categoryTesting.mode != nil {
                categoryReadRoot
            } else if dependencies.homeTesting.root == .catalogFixture {
                categoryFixtureRoot
            } else {
                categoryReadRoot
            }
        #else
            categoryReadRoot
        #endif
    }

    private var categoryReadRoot: some View {
        CategoryEntryView(
            categories: dependencies.category,
            isActive: router.selectedTab == .category && router.categoryPath.isEmpty,
            imagePipeline: dependencies.categoryImagePipeline,
            showsReadVerification: dependencies.showsCategoryReadVerification,
            // F-CATEGORY-05 navigation INTENT only: the real direct-child id is
            // handed to the App; the product list (LIST-01) does not exist yet,
            // so no list page is faked. The explicit unavailable feedback is not
            // evidence that F-CATEGORY-05 is implemented.
            onOpenSubcategory: { id in
                categoryRequestedChildID = id
                categoryUnavailableNotice = UUID()
            }
        )
        .overlay(alignment: .topTrailing) {
            // Controlled DEBUG consumer marker for the approved Int64 callback
            // contract (F-CATEGORY-05 design only): records the real direct-child
            // id without asserting the unavailable placeholder or LIST-01.
            if dependencies.showsCategoryReadVerification {
                Text(verbatim: "请求子分类：\(categoryRequestedChildID.map { String($0) } ?? "无")")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("category.requestedChild")
            }
        }
        .overlay(alignment: .bottom) {
            if categoryUnavailableNotice != nil {
                Text("暂未开放").font(.body).padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding().accessibilityIdentifier("category.unavailable")
            }
        }
        .task(id: categoryUnavailableNotice) {
            guard let notice = categoryUnavailableNotice else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if categoryUnavailableNotice == notice { categoryUnavailableNotice = nil }
        }
    }

    /// NAV-02/NAV-03 engineering shell: same per-tab path probe and fixture
    /// product entry as before the real category page. DEBUG navigation-fixture
    /// launches only; never reachable in normal Debug/Release.
    private var categoryFixtureRoot: some View {
        PendingTabView(
            marker: "category.pending",
            title: "分类",
            detail: "分类页面待接入 · 本入口为导航占位",
            pushProbe: { router.categoryPath.append(.fixturePathProbe(label: "category")) },
            // NAV-03: non-home source entry with the TC-NAV-05 fixture id.
            openProductDetail: {
                router.append(.productDetail(goodsID: 830001), on: .category)
            }
        )
    }

    /// HOME-01 root selection. Normal Debug/Release show the real read UI with
    /// the App-declared source marker; DEBUG launch arguments may keep the F0
    /// catalog fixture root for the navigation suite or select a deterministic
    /// home test service. Conflicting/illegal test arguments stop the read
    /// with an explicit error instead of guessing a mode.
    @ViewBuilder
    private var homeRoot: some View {
        #if DEBUG
            switch dependencies.homeTesting.root {
            case .catalogFixture:
                CatalogEntryView(
                    products: dependencies.products,
                    openCart: router.openCart,
                    openProduct: { id in router.append(.productDetail(goodsID: id), on: .home) }
                )
            case .testConfigError:
                VStack(spacing: 12) {
                    FixtureNoticeView(title: "测试配置错误", detail: "启动参数冲突或非法，已停止读取")
                    Text("home.testConfigError")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("home.testConfigError")
                }
            case .home:
                homeReadRoot
            }
        #else
            homeReadRoot
        #endif
    }

    private var homeReadRoot: some View {
        VStack(spacing: 4) {
            // App-declared source marker; proves assembly choice, not success.
            if dependencies.showsHomeReadVerification {
                Text(verbatim: dependencies.homeSourceDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home.source")
            }
            #if DEBUG
                if dependencies.homeTesting.fixtureMode == .pageControlled {
                    PageHomeTestControlsView()
                }
                if dependencies.homeTesting.fixtureMode == .imageSuccess
                    || dependencies.homeTesting.fixtureMode == .imageFailure
                    || dependencies.homeTesting.fixtureMode == .imagePending
                    || dependencies.homeTesting.fixtureMode == .bannerSingle
                    || dependencies.homeTesting.fixtureMode == .bannerMultiple
                    || dependencies.homeTesting.fixtureMode == .bannerReconcile
                    || dependencies.homeTesting.fixtureMode == .bannerRefreshFailure
                    || dependencies.homeTesting.fixtureMode == .bannerPending
                {
                    ImageUITestMetricsView()
                }
            #endif
            Button(action: showUnavailable) {
                Label("搜索商品", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索")
            .accessibilityIdentifier("home.search")
            .padding(.horizontal, 16)
            HomeEntryView(
                home: dependencies.home,
                isActive: homeIsVisible,
                refreshRequest: router.homeReTapEvent,
                imagePipeline: dependencies.homeImagePipeline,
                allowsBannerAutoplay: allowsBannerAutoplay,
                showsReadVerification: dependencies.showsHomeReadVerification,
                onUnavailableAction: showUnavailable
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.regularMaterial, for: .tabBar)
        .overlay(alignment: .bottom) {
            if unavailableNotice != nil {
                Text("暂未开放").font(.body).padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding().accessibilityIdentifier("home.unavailable")
            }
        }
        .task(id: unavailableNotice) {
            guard let notice = unavailableNotice else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if unavailableNotice == notice { unavailableNotice = nil }
        }
    }

    private func showUnavailable() { unavailableNotice = UUID() }

    /// Pushed routes cover the tab bar (the PRD-016 pattern from NAV-01), so
    /// re-tapping the current tab stays reachable only at tab roots, where the
    /// system pop-to-root is a no-op (PRD-013/NAV-R02; iOS 18+ auto-pops on
    /// tab re-tap and that cannot be vetoed with public API). PRD-017/NAV-R07:
    /// the detail page and the independent cart it opens keep the bar hidden;
    /// returning to the source root restores the four tabs.
    @ViewBuilder
    private func destination(for route: SceneRouter.Route, on tab: SceneRouter.Tab) -> some View {
        switch route {
        case .cart:
            CartEntryView(cart: dependencies.cart)
                .toolbar(.hidden, for: .tabBar)
                .toolbar(.visible, for: .navigationBar)
        case .productDetail(let goodsID):
            // The cart intent from a detail pushes onto the SAME stack, so back
            // restores this detail (same goodsId, same page identity) without
            // touching the source tab (NAV-R03).
            ProductDetailPlaceholderView(
                goodsID: goodsID,
                openCart: { router.append(.cart, on: tab) }
            )
            .toolbar(.hidden, for: .tabBar)
            .toolbar(.visible, for: .navigationBar)
        case .fixturePathProbe(let label):
            FixturePathProbeView(label: label)
                .toolbar(.hidden, for: .tabBar)
                .toolbar(.visible, for: .navigationBar)
        }
    }
}

/// NAV-01 shell placeholders. NAV-02 adds fixture-only path probes (and v0.3
/// root-local identity ticks) so per-tab path behavior and root page identity
/// stay observable until real screens arrive; still no business state.
private struct PendingTabView: View {
    let marker: String
    let title: String
    let detail: String
    let pushProbe: () -> Void
    var openProductDetail: (() -> Void)? = nil
    @State private var rootTicks = 0
    var body: some View {
        VStack(spacing: 20) {
            FixtureNoticeView(title: title, detail: detail)
            Text("待接入").font(.headline).accessibilityIdentifier(marker)
            // Root-local identity ticks (v0.3): a recreated view would restart at
            // zero, so a preserved count proves the root page identity survived
            // tab switches. Fixture scaffolding only, like the probe below.
            Text("根页身份：\(rootTicks)")
                .accessibilityIdentifier("\(marker).rootIdentity")
            Button("根页计数 +1") { rootTicks += 1 }
                .accessibilityIdentifier("\(marker).rootTick")
            if let openProductDetail {
                Button("打开商品详情（夹具 830001）", action: openProductDetail)
                    .accessibilityIdentifier("\(marker).openProduct")
            }
            Button("压入路径自检页", action: pushProbe)
                .accessibilityIdentifier("\(marker).pushProbe")
        }
        .navigationTitle(title)
    }
}

/// NAV-03 engineering fixture: the typed product-detail destination before any
/// real detail screen exists. It only proves route plumbing — the goodsId it
/// received, page identity across an independent-cart round trip, and the cart
/// intent staying on the source stack. No loading, no cart writes, no network,
/// no persistence; superseded by the real detail task.
private struct ProductDetailPlaceholderView: View {
    let goodsID: Int64
    let openCart: () -> Void
    @State private var identityTicks = 0
    var body: some View {
        VStack(spacing: 20) {
            FixtureNoticeView(
                title: "商品详情（工程夹具）",
                detail: "真实详情待接入 · 仅验证类型化导航与商品ID传递"
            )
            // verbatim: keep the raw goodsId (no localized digit grouping).
            Text(verbatim: "商品ID：\(goodsID)")
                .accessibilityIdentifier("detail.goodsID")
            Text("详情身份：\(identityTicks)")
                .accessibilityIdentifier("detail.identity")
            Button("详情身份 +1") { identityTicks += 1 }
                .accessibilityIdentifier("detail.tick")
            Button("打开独立购物车", action: openCart)
                .accessibilityIdentifier("detail.openCart")
        }
        .navigationTitle("商品详情")
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

#if DEBUG
    /// TEST MEANS ONLY (NAV-02 v0.2 supplement): enabled solely by the UI-test
    /// launch argument `--uitest-nav-control`; never compiled into Release and
    /// never a user-reachable control. Pushed routes hide the tab bar, so a user
    /// cannot switch tabs while any path is non-empty; this control seeds initial
    /// per-tab paths (`--uitest-nav-paths home=cart;category=probe;...`) and the
    /// overlay switches tabs programmatically to verify the structural rules.
    /// Results obtained through it must be reported as controlled test evidence,
    /// not as user-reachable interaction.
    private struct NavigationTestControl {
        let isEnabled: Bool
        private let seededPaths: [SceneRouter.Tab: [SceneRouter.Route]]

        @MainActor
        init() {
            let arguments = ProcessInfo.processInfo.arguments
            isEnabled = arguments.contains("--uitest-nav-control")
            var paths: [SceneRouter.Tab: [SceneRouter.Route]] = [:]
            if let flag = arguments.firstIndex(of: "--uitest-nav-paths"), flag + 1 < arguments.count
            {
                for pair in arguments[flag + 1].split(separator: ";") {
                    let parts = pair.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let tabName = String(parts[0])
                    guard let tab = Self.tab(named: tabName) else { continue }
                    paths[tab] =
                        String(parts[1]) == "cart"
                        ? [.cart]
                        : [.fixturePathProbe(label: tabName)]
                }
            }
            seededPaths = paths
        }

        @MainActor
        func seed(into router: SceneRouter) {
            guard isEnabled else { return }
            router.homePath = seededPaths[.home] ?? []
            router.categoryPath = seededPaths[.category] ?? []
            router.cartPath = seededPaths[.cart] ?? []
            router.mePath = seededPaths[.me] ?? []
        }

        private static func tab(named name: String) -> SceneRouter.Tab? {
            switch name {
            case "home": .home
            case "category": .category
            case "cart": .cart
            case "me": .me
            default: nil
            }
        }
    }

    /// Visible test bar, explicitly labeled so screenshots and logs cannot be
    /// mistaken for product UI. Switches the selected tab programmatically.
    /// Rendered as a bottom strip that reserves its own layout space
    /// (R-NAV-02-AT05-01). At accessibility sizes the content regroups instead
    /// of truncating: one row, then two grouped rows, then one item per row;
    /// fixedSize keeps every label at its full single-line ideal width.
    /// The container must not set an accessibilityIdentifier: it would override
    /// the per-button identifiers the UI tests query.
    private struct NavigationTestControlOverlay: View {
        let router: SceneRouter
        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    marking
                    controlButton("home", tab: .home)
                    controlButton("category", tab: .category)
                    controlButton("cart", tab: .cart)
                    controlButton("me", tab: .me)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        marking
                        controlButton("home", tab: .home)
                        controlButton("category", tab: .category)
                    }
                    HStack(spacing: 12) {
                        controlButton("cart", tab: .cart)
                        controlButton("me", tab: .me)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    marking
                    controlButton("home", tab: .home)
                    controlButton("category", tab: .category)
                    controlButton("cart", tab: .cart)
                    controlButton("me", tab: .me)
                }
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }

        private var marking: some View {
            Text("受控测试").fixedSize()
        }

        private func controlButton(_ name: String, tab: SceneRouter.Tab) -> some View {
            Button("→\(name)") { router.selectedTab = tab }
                .fixedSize()
                .accessibilityIdentifier("navctl.select.\(name)")
        }
    }
#endif
