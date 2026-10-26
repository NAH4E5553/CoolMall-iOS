import OrdersFeature
import CheckoutFeature
import AccountFeature
import CartFeature
import CatalogFeature
import Foundation
import MallDesignSystem
import MallCore
import SwiftUI

@MainActor
struct RootView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var accountScenePhase
    @State private var router = SceneRouter()
    @State private var cartBadge = CartBadgeViewModel()
    @State private var observedAccount: AccountState?
    #if DEBUG
        @Environment(\.scenePhase) private var bannerAuditScenePhase
    #endif
    private struct ClaimPresentation: Identifiable {
        let id = UUID()
        let offers: [CouponClaimOffer]
    }
    @State private var claimPresentation: ClaimPresentation?
    private struct AddressSelection: Identifiable {
        let id = UUID(); let accountID: Int64; let choose: @MainActor (ShippingAddress) -> Void
    }
    @State private var addressSelection: AddressSelection?
    @State private var cartCleanupNotice: UUID?
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
        rootContent
            .allowsHitTesting(claimPresentation == nil)
            .accessibilityHidden(claimPresentation != nil)
            .overlay {
                if let presentation = claimPresentation {
                    CouponReceiveEntryView(
                        offers: presentation.offers, state: dependencies.accountState,
                        receiver: dependencies.couponReceiver, session: dependencies.accountSession,
                        challenges: dependencies.loginChallenges,
                        notifier: dependencies.codeNotifier,
                        onDismiss: { claimPresentation = nil }
                    ).id(presentation.id)
                }
            }
            .sheet(item: $addressSelection) { selection in
                CheckoutAddressSheet(
                    accountID: selection.accountID, loader: dependencies.addresses,
                    writer: dependencies.addresses, regions: dependencies.addressRegions,
                    onSelect: { address in
                        guard dependencies.accountState.profile?.id == selection.accountID,
                            addressSelection?.id == selection.id
                        else { return }
                        selection.choose(address); addressSelection = nil
                    })
            }
            .overlay(alignment: .bottom) {
                if cartCleanupNotice != nil {
                    Text("订单已创建，购物车未同步，请核对后手动删除已下单商品")
                        .font(.subheadline).foregroundStyle(.white).padding(14)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        .padding().allowsHitTesting(false).accessibilityIdentifier(
                            "order.cartCleanupNotice")
                }
            }
            .task(id: cartCleanupNotice) {
                guard let notice = cartCleanupNotice else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                if cartCleanupNotice == notice { cartCleanupNotice = nil }
            }
            .task {
                for await state in await dependencies.accountSession.states() {
                    guard !Task.isCancelled else { return }
                    let old = observedAccount ?? dependencies.accountState
                    dependencies.applyAccount(state)
                    observedAccount = state
                    if old.profile?.id != state.profile?.id || (state == .guest && old != .guest) {
                        let resumesCoupons =
                            old == .guest && state.profile != nil
                            && (router.mePath == [.coupons] || router.mePath == [.addresses]
                                || router.hasMeOrderIntent)
                        router.updateOrderAccount(old: old.profile?.id, new: state.profile?.id)
                        addressSelection = nil
                        if !resumesCoupons { router.mePath = [] }
                    }
                }
            }
            .onChange(of: accountScenePhase) { _, phase in
                // Selection is cancelled on interruption; a resumed picker must obtain a new callback.
                if phase != .active { addressSelection = nil }
            }
            .task(id: dependencies.shoppingCart.scope) {
                if !usesCartFixture {
                    await cartBadge.observe(dependencies.shoppingCart)
                }
            }
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

    @ViewBuilder private var rootContent: some View {
        #if DEBUG
            if let fixture = dependencies.productDetailTesting, fixture.holdsCartIncrease {
                // A sibling reserves actual space outside TabView; an inset on
                // TabView can overlap its native tab bar at accessibility sizes.
                VStack(spacing: 0) {
                    Button("完成测试核验") {
                        Task { await fixture.releaseCartIncrease() }
                    }
                    .font(.caption).frame(minHeight: 44)
                    .accessibilityIdentifier("cart.fixture.releaseIncrease")
                    tabs
                }
            } else {
                tabs
            }
        #else
            tabs
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
            NavigationStack(
                path: Binding(get: { router.homePath }, set: { router.setPath($0, on: .home) })
            ) {
                homeRoot
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        destination(for: route, on: .home)
                    }
            }
            .tabItem { Label("首页", systemImage: "house") }
            .tag(SceneRouter.Tab.home)
            NavigationStack(
                path: Binding(
                    get: { router.categoryPath }, set: { router.setPath($0, on: .category) })
            ) {
                categoryRoot
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        destination(for: route, on: .category)
                    }
            }
            .tabItem { Label("分类", systemImage: "square.grid.2x2") }
            .tag(SceneRouter.Tab.category)
            NavigationStack(
                path: Binding(get: { router.cartPath }, set: { router.setPath($0, on: .cart) })
            ) {
                cartEntry(on: .cart, root: true)
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        destination(for: route, on: .cart)
                    }
            }
            .tabItem { Label("购物车", systemImage: "cart") }
            .badge(
                cartBadge.scope == dependencies.shoppingCart.scope
                    ? cartBadge.count.flatMap { $0 > 0 ? String($0) : nil } : nil
            )
            .tag(SceneRouter.Tab.cart)
            NavigationStack(
                path: Binding(get: { router.mePath }, set: { router.setPath($0, on: .me) })
            ) {
                meRoot
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        destination(for: route, on: .me)
                    }
            }
            .tabItem { Label("我的", systemImage: "person") }
            .tag(SceneRouter.Tab.me)
        }
    }

    @ViewBuilder private var meRoot: some View {
        if usesCartFixture {
            PendingTabView(
                marker: "me.pending", title: "我的", detail: "个人中心待接入 · 本入口为导航占位",
                pushProbe: { router.mePath.append(.fixturePathProbe(label: "me")) })
        } else {
            MeEntryView(
                state: dependencies.accountState, imagePipeline: dependencies.detailImagePipeline,
                footprints: dependencies.footprints,
                isActive: router.selectedTab == .me && router.mePath.isEmpty
                    && accountScenePhase == .active,
                onOpenFootprints: { router.mePath.append(.footprints) },
                onOpenCoupons: { router.mePath.append(.coupons) },
                onOpenAddresses: { router.mePath.append(.addresses) },
                onOpenOrders: { router.mePath.append(.orders(filter: $0)) },
                onOpenProduct: { router.mePath.append(.productDetail(goodsID: $0)) }
            ) {
                if case .guest = dependencies.accountState {
                    router.mePath.append(.login)
                } else {
                    router.mePath.append(.profile)
                }
            }
        }
    }

    /// Home is visible only at its own tab root; pushed routes and other tabs
    /// make the home read inactive (H0 visibility contract).
    private var homeIsVisible: Bool {
        router.selectedTab == .home && router.homePath.isEmpty
    }

    /// Coupon presentations pause playback while home images remain active.
    /// Explicit DEBUG fixture launches may also suppress playback for manual tests.
    private var allowsBannerAutoplay: Bool {
        guard claimPresentation == nil else { return false }
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
                if dependencies.homeTesting.fixtureMode == .couponMany {
                    ImageUITestMetricsView(compact: true)
                }
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
                onUnavailableAction: showUnavailable,
                onOpenProduct: { router.append(.productDetail(goodsID: $0), on: .home) },
                onReceiveCoupons: beginClaims
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

    @ViewBuilder
    private func productDetail(goodsID: Int64, on tab: SceneRouter.Tab) -> some View {
        #if DEBUG
            if case .catalogFixture = dependencies.homeTesting.root {
                // Only the pre-existing explicit navigation fixture retains its
                // identity/cart probe. Normal Debug and Release use the real entry.
                ProductDetailPlaceholderView(
                    goodsID: goodsID,
                    openCart: { router.append(.cart, on: tab) }
                )
                .toolbar(.visible, for: .navigationBar)
            } else {
                realProductDetail(goodsID: goodsID, on: tab)
            }
        #else
            realProductDetail(goodsID: goodsID, on: tab)
        #endif
    }

    private func realProductDetail(goodsID: Int64, on tab: SceneRouter.Tab) -> some View {
        let path: [SceneRouter.Route]
        switch tab {
        case .home: path = router.homePath
        case .category: path = router.categoryPath
        case .cart: path = router.cartPath
        case .me: path = router.mePath
        }
        return ProductDetailEntryView(
            productID: goodsID, loader: dependencies.productDetails,
            imagePipeline: dependencies.detailImagePipeline,
            isActive: router.selectedTab == tab && path.last == .productDetail(goodsID: goodsID)
                && claimPresentation == nil,
            onShowAllReviews: { router.append(.productReviews(goodsID: $0), on: tab) },
            footprintRecorder: dependencies.footprints,
            shoppingCart: dependencies.shoppingCart,
            cartVerifier: dependencies.cartVerifier,
            onOpenCart: { router.append(.cart, on: tab) }, onReceiveCoupon: beginClaim,
            onBuyNow: {
                router.beginPurchase($0, accountID: dependencies.accountState.profile?.id, on: tab)
            }
        )
    }

    private func beginClaim(_ offer: CouponClaimOffer) { beginClaims([offer]) }
    private func beginClaims(_ offers: [CouponClaimOffer]) {
        guard claimPresentation == nil, !offers.isEmpty,
            Set(offers.map(\.id)).count == offers.count,
            offers.allSatisfy({ $0.id > 0 && !$0.title.isEmpty })
        else { return }
        claimPresentation = ClaimPresentation(offers: offers)
    }
    private var usesCartFixture: Bool {
        #if DEBUG
            navTestControl.isEnabled
                || ProcessInfo.processInfo.arguments.contains("--uitest-nav-fixture")
        #else
            false
        #endif
    }

    @ViewBuilder
    private func cartEntry(on tab: SceneRouter.Tab, root: Bool) -> some View {
        #if DEBUG
            if usesCartFixture {
                CartEntryView(cart: dependencies.cart)
            } else {
                productionCart(on: tab, root: root)
            }
        #else
            productionCart(on: tab, root: root)
        #endif
    }
    private func productionCart(on tab: SceneRouter.Tab, root: Bool) -> some View {
        productionCartContent(on: tab, root: root)
    }
    private func productionCartContent(on tab: SceneRouter.Tab, root: Bool) -> some View {
        let path: [SceneRouter.Route]
        switch tab {
        case .home: path = router.homePath
        case .category: path = router.categoryPath
        case .cart: path = router.cartPath
        case .me: path = router.mePath
        }
        return CartEntryView(
            store: dependencies.shoppingCart, verifier: dependencies.cartVerifier,
            imagePipeline: dependencies.detailImagePipeline,
            isActive: router.selectedTab == tab && (root ? path.isEmpty : path.last == .cart),
            onOpenProduct: { router.append(.productDetail(goodsID: $0), on: tab) },
            onCheckout: { intent in
                router.beginCartPurchase(
                    intent, accountID: dependencies.accountState.profile?.id, on: tab)
            }
        )
        .id(dependencies.shoppingCart.scope)
    }

    /// Pushed routes cover the tab bar (the PRD-016 pattern from NAV-01), so
    /// re-tapping the current tab stays reachable only at tab roots, where the
    /// system pop-to-root is a no-op (PRD-013/NAV-R02; iOS 18+ auto-pops on
    /// tab re-tap and that cannot be vetoed with public API). PRD-017/NAV-R07:
    /// the detail page and the independent cart it opens keep the bar hidden;
    /// returning to the source root restores the four tabs.
    private func orderLogin(on tab: SceneRouter.Tab) -> some View {
        LoginEntryView(
            session: dependencies.accountSession, challenges: dependencies.loginChallenges,
            notifier: dependencies.codeNotifier,
            isActive: router.selectedTab == tab && accountScenePhase != .background,
            onAuthenticated: {})
    }

    @ViewBuilder
    private func destination(for route: SceneRouter.Route, on tab: SceneRouter.Tab) -> some View {
        switch route {
        case .login:
            LoginEntryView(
                session: dependencies.accountSession, challenges: dependencies.loginChallenges,
                notifier: dependencies.codeNotifier,
                isActive: router.selectedTab == tab && accountScenePhase != .background,
                onAuthenticated: {
                    switch tab {
                    case .home: router.homePath.removeAll { $0 == .login }
                    case .category: router.categoryPath.removeAll { $0 == .login }
                    case .cart: router.cartPath.removeAll { $0 == .login }
                    case .me:
                        if router.hasMeOrderIntent {
                            router.mePath.removeAll { $0 == .login }
                        } else {
                            router.mePath = router.mePath.contains(.coupons) ? [.coupons] : []
                        }
                    }
                }
            )
            .toolbar(.hidden, for: .tabBar)
            .toolbar(.visible, for: .navigationBar)
        case .coupons:
            Group {
                if let profile = dependencies.accountState.profile {
                    CouponEntryView(
                        accountID: profile.id, loader: dependencies.userCoupons,
                        isActive: router.selectedTab == tab && router.mePath.last == .coupons,
                        onUse: { router.append(.couponProducts(minimumPriceYuan: $0), on: tab) },
                        onRequestLogin: { router.append(.login, on: tab) })
                } else {
                    LoginEntryView(
                        session: dependencies.accountSession,
                        challenges: dependencies.loginChallenges,
                        notifier: dependencies.codeNotifier,
                        isActive: router.selectedTab == tab && router.mePath.last == .coupons
                            && accountScenePhase != .background,
                        onAuthenticated: {})
                }
            }.toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .addresses:
            Group {
                if let profile = dependencies.accountState.profile {
                    AddressEntryView(
                        accountID: profile.id, loader: dependencies.addresses,
                        writer: dependencies.addresses,
                        isActive: router.selectedTab == tab && router.mePath.last == .addresses,
                        onEdit: { router.append(.addressEditor(id: $0), on: tab) })
                } else {
                    LoginEntryView(
                        session: dependencies.accountSession,
                        challenges: dependencies.loginChallenges,
                        notifier: dependencies.codeNotifier,
                        isActive: router.selectedTab == tab && router.mePath.last == .addresses
                            && accountScenePhase != .background,
                        onAuthenticated: {})
                }
            }.toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .addressEditor(let id):
            Group {
                if let profile = dependencies.accountState.profile {
                    AddressEditorEntryView(
                        accountID: profile.id, id: id, loader: dependencies.addresses,
                        writer: dependencies.addresses,
                        regions: dependencies.addressRegions,
                        isActive: router.selectedTab == tab && router.mePath.last == route,
                        onSaved: { if router.mePath.last == route { router.mePath.removeLast() } })
                }
            }.toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .couponProducts(let minimum):
            CouponProductsEntryView(
                minimumPriceYuan: minimum, loader: dependencies.couponProducts,
                imagePipeline: dependencies.detailImagePipeline,
                isActive: router.selectedTab == tab && router.mePath.last == route,
                onOpenProduct: { router.append(.productDetail(goodsID: $0), on: tab) }
            )
            .id(minimum).toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .footprints:
            FootprintEntryView(
                store: dependencies.footprints, imagePipeline: dependencies.detailImagePipeline,
                isActive: router.selectedTab == tab && router.mePath.last == .footprints,
                onOpenProduct: { router.append(.productDetail(goodsID: $0), on: tab) }
            )
            .toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .orders(let filter):
            Group {
                if let profile = dependencies.accountState.profile {
                    OrderListEntryView(
                        accountID: profile.id, filter: filter, loader: dependencies.orders,
                        isActive: router.selectedTab == tab && router.path(on: tab).last == route,
                        imagePipeline: dependencies.detailImagePipeline,
                        onRequestLogin: { router.append(.login, on: tab) },
                        onOpenOrder: { router.append(.orderDetail(id: $0), on: tab) },
                        refreshRevision: router.orderRevision)
                } else {
                    orderLogin(on: tab)
                }
            }.toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .orderDetail(let id):
            Group {
                if let profile = dependencies.accountState.profile {
                    OrderDetailEntryView(
                        accountID: profile.id, orderID: id, loader: dependencies.orders,
                        isActive: router.selectedTab == tab && router.path(on: tab).last == route,
                        imagePipeline: dependencies.detailImagePipeline,
                        onRequestLogin: { router.append(.login, on: tab) },
                        canceller: dependencies.orderCanceller,
                        onCashier: {
                            guard router.path(on: tab).last == route else { return };
                            router.append(.cashier(orderID: id), on: tab)
                        },
                        onChanged: { router.orderChanged() })
                } else {
                    orderLogin(on: tab)
                }
            }.toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .checkout(let intent, let accountID):
            Group {
                if let profile = dependencies.accountState.profile, accountID == profile.id {
                    CheckoutEntryView(
                        accountID: profile.id, intent: intent, loader: dependencies.checkout,
                        isActive: router.selectedTab == tab && router.path(on: tab).last == route,
                        imagePipeline: dependencies.detailImagePipeline,
                        onRequestLogin: { router.append(.login, on: tab) },
                        onChooseAddress: { callback in
                            guard router.path(on: tab).last == route else { return }
                            addressSelection = AddressSelection(
                                accountID: profile.id, choose: callback)
                        }, creator: dependencies.orderCreator,
                        cart: dependencies.checkoutCart(for: intent),
                        onCartCleanupFailure: { cartCleanupNotice = UUID() },
                        onCreated: { id in
                            guard dependencies.accountState.profile?.id == profile.id else {
                                return
                            }
                            router.orderCreated(id, from: route, on: tab)
                        })
                } else if dependencies.accountState.profile == nil {
                    orderLogin(on: tab)
                }
            }.toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .cashier(let id):
            Group {
                if let profile = dependencies.accountState.profile {
                    CashierEntryView(
                        accountID: profile.id, orderID: id, loader: dependencies.orders,
                        isActive: router.selectedTab == tab && router.path(on: tab).last == route,
                        onBack: { router.cashierBack(on: tab) },
                        onRequestLogin: { router.append(.login, on: tab) })
                } else {
                    orderLogin(on: tab)
                }
            }.toolbar(.hidden, for: .tabBar).toolbar(.visible, for: .navigationBar)
        case .profile:
            ProfileEntryView(
                state: dependencies.accountState, session: dependencies.accountSession,
                imagePipeline: dependencies.detailImagePipeline
            )
            .toolbar(.hidden, for: .tabBar)
            .toolbar(.visible, for: .navigationBar)
        case .cart:
            cartEntry(on: tab, root: false)
                .toolbar(.hidden, for: .tabBar)
                .toolbar(.visible, for: .navigationBar)
        case .productDetail(let goodsID):
            productDetail(goodsID: goodsID, on: tab)
                .toolbar(.hidden, for: .tabBar)
        case .productReviews(let goodsID):
            ProductReviewsEntryView(
                productID: goodsID, loader: dependencies.productReviews,
                imagePipeline: dependencies.detailImagePipeline,
                isActive: router.selectedTab == tab
            )
            .toolbar(.hidden, for: .tabBar)
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
#if DEBUG
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

#endif

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

/// App composes the address Feature without creating a cross-Feature dependency.
@MainActor private struct CheckoutAddressSheet: View {
    private struct Editor: Hashable { let id: Int64? }
    @State private var path: [Editor] = []
    let accountID: Int64
    let loader: any AddressLoading
    let writer: any AddressWriting
    let regions: any AddressRegionsLoading
    let onSelect: (ShippingAddress) -> Void
    var body: some View {
        NavigationStack(path: $path) {
            AddressEntryView(
                accountID: accountID, loader: loader, writer: writer,
                isActive: path.isEmpty, onEdit: { path.append(Editor(id: $0)) }, onSelect: onSelect
            )
            .navigationDestination(for: Editor.self) { editor in
                AddressEditorEntryView(
                    accountID: accountID, id: editor.id, loader: loader, writer: writer,
                    regions: regions, isActive: path.last == editor,
                    onSaved: { if path.last == editor { path.removeLast() } })
            }
        }.tint(Color(red: 0.29, green: 0.32, blue: 1))
    }
}
