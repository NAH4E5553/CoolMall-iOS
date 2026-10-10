import XCTest

final class NavigationSmokeTests: XCTestCase {
    @MainActor func testCatalogRouteOpensCartAndReturns() {
        let app = launchApp()
        app.buttons["catalog.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openCart"].waitForExistence(timeout: 5))
    }

    @MainActor func testFeatureTabsSwitchAndReturn() {
        let app = launchApp()
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
    }

    @MainActor func testColdStartDefaultsToHomeWithFourTabs() {
        let app = launchApp()
        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(tabs.element(boundBy: 0).label, "首页")
        XCTAssertEqual(tabs.element(boundBy: 1).label, "分类")
        XCTAssertEqual(tabs.element(boundBy: 2).label, "购物车")
        XCTAssertEqual(tabs.element(boundBy: 3).label, "我的")
        XCTAssertTrue(app.staticTexts["真实首页待接入 · 当前展示本地工程夹具"].waitForExistence(timeout: 5))
    }

    @MainActor func testPendingTabsShowMarkersAndCartStaysFixture() {
        let app = launchApp()
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
    }

    /// Re-tapping the current tab is only reachable while the tab bar is visible, i.e.
    /// at tab roots with an empty path; the system pop is a no-op there (PRD-013/NAV-R02).
    @MainActor func testRepeatedCurrentTabTapsDoNotAlterPageOrPath() {
        let app = launchApp()
        for _ in 0..<3 { app.tabBars.buttons["首页"].tap() }
        XCTAssertTrue(app.staticTexts["catalog.fixture"].exists)
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.tabBars.buttons["购物车"].tap() }
        XCTAssertTrue(app.staticTexts["cart.fixture"].exists)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].exists)
    }

    /// The independent cart route covers the tab bar (Android reference); the native
    /// back button restores it, so the re-tap auto-pop can never reach the pushed route.
    @MainActor func testCartRouteHidesTabBarAndBackRestoresIt() {
        let app = launchApp()
        app.buttons["catalog.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["首页"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openCart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
    }

    /// NAV-02: each path entry owns a fresh page identity; back pops only the
    /// current stack; the pending-tab probes leave every other tab root untouched.
    @MainActor func testFixtureProbePathPushBackAndIdentityPerEntry() {
        let app = launchApp()
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["category.pending.pushProbe"].tap()
        XCTAssertTrue(app.staticTexts["category.probeIdentity"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["category.probeIdentity"].label, "身份计数：0")
        app.buttons["category.probeTick"].tap()
        app.buttons["category.probeTick"].tap()
        XCTAssertEqual(app.staticTexts["category.probeIdentity"].label, "身份计数：2")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["category.pending.pushProbe"].tap()
        XCTAssertTrue(app.staticTexts["category.probeIdentity"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["category.probeIdentity"].label, "身份计数：0")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        app.buttons["me.pending.pushProbe"].tap()
        XCTAssertTrue(app.staticTexts["me.probeIdentity"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
    }

    /// NAV-02: pushed fixture routes cover the tab bar and native back restores
    /// it — the same PRD-016 pattern the NAV-01 independent cart uses.
    @MainActor func testFixtureProbeHidesTabBarAndBackRestoresIt() {
        let app = launchApp()
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["category.pending.pushProbe"].tap()
        XCTAssertTrue(app.staticTexts["category.probeIdentity"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["首页"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
    }

    /// NAV-02 (NAV-R02): re-tapping the current tab at any tab root is a no-op —
    /// no push, pop, or refresh. Extends the NAV-01 home/cart coverage to the
    /// pending tab roots.
    /// Split for the CI per-test time budget (same CHANGE-04 pattern; every
    /// assertion kept). This half: category root re-taps.
    @MainActor func testRepeatedCategoryRootTapsStayPut() {
        let app = launchApp()
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.tabBars.buttons["分类"].tap() }
        XCTAssertTrue(app.staticTexts["category.pending"].exists)
    }

    /// Companion half: me-root and home-root re-taps.
    @MainActor func testRepeatedMeAndHomeRootTapsStayPut() {
        let app = launchApp()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.tabBars.buttons["我的"].tap() }
        XCTAssertTrue(app.staticTexts["me.pending"].exists)
        app.tabBars.buttons["首页"].tap()
        for _ in 0..<3 { app.tabBars.buttons["首页"].tap() }
        XCTAssertTrue(app.staticTexts["catalog.fixture"].exists)
    }

    /// NAV-02: per-tab stacks never cross — home cart pushes keep working around
    /// category stack operations, and each back pops only its own stack.
    @MainActor func testHomeCartPathIndependentFromCategoryStack() {
        let app = launchApp()
        app.buttons["catalog.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openCart"].waitForExistence(timeout: 5))
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["category.pending.pushProbe"].tap()
        XCTAssertTrue(app.staticTexts["category.probeIdentity"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
        app.buttons["catalog.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openCart"].waitForExistence(timeout: 5))
    }

    /// NAV-02 v0.2/v0.3 (user-reachable operations), split for the CI per-test
    /// time budget (same CHANGE-04 pattern as the earlier splits; every
    /// assertion kept): a tab round trip preserves each root's observable
    /// state. This half keeps the home/cart fixture labels identical before and
    /// after two away-and-back cycles; the pending roots' local identity ticks
    /// live in the companion test. The label check alone cannot distinguish
    /// recreation; the active-instance diagnostics for home/cart live in the
    /// NAV-02 evidence.
    @MainActor func testTabRoundTripPreservesFixtureRootLabels() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
        let homeRootLabel = app.staticTexts["catalog.fixture"].label
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        let cartRootLabel = app.staticTexts["cart.fixture"].label
        for _ in 0..<2 {
            app.tabBars.buttons["首页"].tap()
            XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["catalog.fixture"].label, homeRootLabel)
            app.tabBars.buttons["购物车"].tap()
            XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["cart.fixture"].label, cartRootLabel)
        }
    }

    /// Companion of the test above: pending roots keep their local identity
    /// ticks (a recreated view would restart at zero). v0.6 correction — the
    /// CI-time split had dropped the SECOND consecutive away-and-back round
    /// (2 assertions per root instead of the pre-split 3); these tests restore
    /// it. Split is per root, never per round: each root gets its initial
    /// count plus TWO consecutive switch-away-and-back verifications in one
    /// launch — a fresh launch may not stand in for the second round.
    @MainActor func testTabRoundTripKeepsCategoryRootCountAcrossTwoRounds() {
        let app = launchApp()
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["category.pending.rootTick"].tap()
        app.buttons["category.pending.rootTick"].tap()
        XCTAssertEqual(app.staticTexts["category.pending.rootIdentity"].label, "根页身份：2")
        // Round 1: away to the me root, then back.
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["category.pending.rootIdentity"].label, "根页身份：2")
        // Round 2 (consecutive, same launch): away to a fixture root, then back.
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["category.pending.rootIdentity"].label, "根页身份：2")
    }

    /// Companion half for the me root: initial count plus two consecutive
    /// away-and-back rounds in one launch (away targets: category root, then
    /// the cart fixture root).
    @MainActor func testTabRoundTripKeepsMeRootCountAcrossTwoRounds() {
        let app = launchApp()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        app.buttons["me.pending.rootTick"].tap()
        app.buttons["me.pending.rootTick"].tap()
        XCTAssertEqual(app.staticTexts["me.pending.rootIdentity"].label, "根页身份：2")
        // Round 1: away to the category root, then back.
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["me.pending.rootIdentity"].label, "根页身份：2")
        // Round 2 (consecutive, same launch): away to a fixture root, then back.
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["me.pending.rootIdentity"].label, "根页身份：2")
    }

    /// NAV-02 v0.2/v0.3/v0.5 CONTROLLED TEST MEANS — not user-reachable
    /// interaction. Pushed routes hide the tab bar, so a user cannot switch
    /// tabs while any path is non-empty; the DEBUG-only launch argument seeds
    /// all four paths (including cartPath) and the labeled overlay switches
    /// tabs programmatically. Originally one test; split into independently
    /// launched tests after CI exceeded the 60s per-test budget — same
    /// CHANGE-04 pattern as the NAV-01 smoke split, no assertions removed.
    /// Together they cover probe identity across switches for every path and
    /// back popping only the current stack. They supplement — never replace —
    /// TC-NAV-04, whose user-reachable scenario stays 未验证.
    @MainActor func testControlledProbeIdentityAcrossSwitchesCategoryAndCart() {
        let app = launchControlledApp()
        // Home is selected with its cart route pushed: all four paths non-empty.
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 10))
        let homeCartRouteLabel = app.staticTexts["cart.fixture"].label

        // Category probe: tick to 2, switch away and back, identity preserved.
        app.buttons["navctl.select.category"].tap()
        XCTAssertTrue(app.staticTexts["category.probeIdentity"].waitForExistence(timeout: 5))
        app.buttons["category.probeTick"].tap()
        app.buttons["category.probeTick"].tap()
        XCTAssertEqual(app.staticTexts["category.probeIdentity"].label, "身份计数：2")
        app.buttons["navctl.select.home"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.fixture"].label, homeCartRouteLabel)
        app.buttons["navctl.select.category"].tap()
        XCTAssertTrue(app.staticTexts["category.probeIdentity"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["category.probeIdentity"].label, "身份计数：2")

        // Cart probe (cartPath): same identity sequence across switches.
        app.buttons["navctl.select.cart"].tap()
        XCTAssertTrue(app.staticTexts["cart.probeIdentity"].waitForExistence(timeout: 5))
        app.buttons["cart.probeTick"].tap()
        app.buttons["cart.probeTick"].tap()
        XCTAssertEqual(app.staticTexts["cart.probeIdentity"].label, "身份计数：2")
        app.buttons["navctl.select.me"].tap()
        XCTAssertTrue(app.staticTexts["me.probeIdentity"].waitForExistence(timeout: 5))
        app.buttons["navctl.select.cart"].tap()
        XCTAssertTrue(app.staticTexts["cart.probeIdentity"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.probeIdentity"].label, "身份计数：2")
    }

    /// Controlled companion of the test above: the me probe (mePath) keeps
    /// identity across switches and the home .cart route keeps its observable
    /// label. Same launch arguments; same boundaries.
    @MainActor func testControlledProbeIdentityAcrossSwitchesMeAndHomeCart() {
        let app = launchControlledApp()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 10))

        // Me probe (mePath): tick to 2, switch away and back, identity preserved.
        app.buttons["navctl.select.me"].tap()
        XCTAssertTrue(app.staticTexts["me.probeIdentity"].waitForExistence(timeout: 5))
        app.buttons["me.probeTick"].tap()
        app.buttons["me.probeTick"].tap()
        XCTAssertEqual(app.staticTexts["me.probeIdentity"].label, "身份计数：2")
        app.buttons["navctl.select.home"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.buttons["navctl.select.me"].tap()
        XCTAssertTrue(app.staticTexts["me.probeIdentity"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["me.probeIdentity"].label, "身份计数：2")
    }

    /// Controlled companion of the test above: back pops only the current
    /// stack, and every seeded path (home/category/cart/me incl. cartPath)
    /// pops to its own tab root. Same launch arguments; same boundaries.
    @MainActor func testControlledBackPopsOnlyCurrentStackAcrossFourPaths() {
        let app = launchControlledApp()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 10))
        let homeCartRouteLabel = app.staticTexts["cart.fixture"].label

        // Back on category pops only this stack; home's path is untouched.
        app.buttons["navctl.select.category"].tap()
        XCTAssertTrue(app.staticTexts["category.probeIdentity"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["navctl.select.home"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.fixture"].label, homeCartRouteLabel)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openCart"].waitForExistence(timeout: 5))

        // Cart probe (cartPath) pops to the cart tab root.
        app.buttons["navctl.select.cart"].tap()
        XCTAssertTrue(app.staticTexts["cart.probeIdentity"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))

        // Me probe (mePath) pops to the me tab root.
        app.buttons["navctl.select.me"].tap()
        XCTAssertTrue(app.staticTexts["me.probeIdentity"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
    }

    /// NAV-03 AT-01: the home fixture emits a typed goodsId intent; the detail
    /// placeholder shows the received id and the pending marker; NAV-R07 keeps
    /// the tab bar hidden on the detail; back restores the home root and the
    /// four tabs.
    @MainActor func testProductDetailRoutePassesIDAndRestoresSourceRoot() {
        let app = launchApp()
        app.buttons["catalog.openProduct"].tap()
        XCTAssertTrue(app.staticTexts["detail.goodsID"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.goodsID"].label, "商品ID：1")
        XCTAssertTrue(app.staticTexts["真实详情待接入 · 仅验证类型化导航与商品ID传递"].exists)
        XCTAssertFalse(app.tabBars.buttons["首页"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openProduct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
    }

    /// NAV-03 AT-02: detail → independent cart → back restores the SAME detail
    /// (same goodsId, same page identity via the detail tick) without swapping
    /// the source tab; the tab bar stays hidden through the round trip and is
    /// restored only at the home root.
    @MainActor func testDetailIndependentCartReturnKeepsDetailIDAndIdentity() {
        let app = launchApp()
        app.buttons["catalog.openProduct"].tap()
        XCTAssertTrue(app.staticTexts["detail.goodsID"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.goodsID"].label, "商品ID：1")
        app.buttons["detail.tick"].tap()
        app.buttons["detail.tick"].tap()
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "详情身份：2")
        app.buttons["detail.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["首页"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["detail.goodsID"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.goodsID"].label, "商品ID：1")
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "详情身份：2")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openProduct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
    }

    /// NAV-03 AT-03: a NON-home source — the category placeholder entry pushes
    /// goodsID 830001 (the TC-NAV-05 fixture value); the independent cart is
    /// opened from that detail and returns to the same detail on the category
    /// stack; back lands on the category root (source tab kept), and the home
    /// stack is untouched.
    @MainActor func testCategoryDetailSourceKeepsSourceTabAndHomeStack() {
        let app = launchApp()
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["category.pending.openProduct"].tap()
        XCTAssertTrue(app.staticTexts["detail.goodsID"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.goodsID"].label, "商品ID：830001")
        app.buttons["detail.tick"].tap()
        app.buttons["detail.tick"].tap()
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "详情身份：2")
        app.buttons["detail.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["首页"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["detail.goodsID"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.goodsID"].label, "商品ID：830001")
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "详情身份：2")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["catalog.openCart"].exists)
    }

    @MainActor private func launchControlledApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-nav-fixture",
            "--uitest-nav-control",
            "--uitest-nav-paths",
            "home=cart;category=probe;cart=probe;me=probe",
        ]
        app.launch()
        return app
    }

    @MainActor private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // HOME-01 moved the home root to the real read UI; the navigation
        // suite keeps the F0 catalog fixture home via the DEBUG launch mode.
        app.launchArguments += ["--uitest-nav-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 10))
        return app
    }
}
