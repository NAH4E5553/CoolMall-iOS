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
    @MainActor func testRepeatedCurrentTabTapsOnPendingRootsStayPut() {
        let app = launchApp()
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.tabBars.buttons["分类"].tap() }
        XCTAssertTrue(app.staticTexts["category.pending"].exists)
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

    /// NAV-02 v0.2/v0.3 (user-reachable operations): a full tab round trip
    /// preserves each tab root's observable state — pending roots keep their
    /// local identity ticks (a recreated view would restart at zero), and the
    /// home/cart fixture labels stay identical before and after. The home/cart
    /// label check alone cannot distinguish recreation; active-instance
    /// diagnostics for those two roots live in the NAV-02 evidence batch.
    @MainActor func testTabRoundTripPreservesRootObservableState() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
        let homeRootLabel = app.staticTexts["catalog.fixture"].label
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        let cartRootLabel = app.staticTexts["cart.fixture"].label
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["category.pending.rootTick"].tap()
        app.buttons["category.pending.rootTick"].tap()
        XCTAssertEqual(app.staticTexts["category.pending.rootIdentity"].label, "根页身份：2")
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        app.buttons["me.pending.rootTick"].tap()
        app.buttons["me.pending.rootTick"].tap()
        XCTAssertEqual(app.staticTexts["me.pending.rootIdentity"].label, "根页身份：2")
        for _ in 0..<2 {
            app.tabBars.buttons["首页"].tap()
            XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["catalog.fixture"].label, homeRootLabel)
            app.tabBars.buttons["购物车"].tap()
            XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["cart.fixture"].label, cartRootLabel)
            app.tabBars.buttons["分类"].tap()
            XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["category.pending.rootIdentity"].label, "根页身份：2")
            app.tabBars.buttons["我的"].tap()
            XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["me.pending.rootIdentity"].label, "根页身份：2")
        }
    }

    /// NAV-02 v0.2/v0.3 CONTROLLED TEST MEANS — not user-reachable interaction.
    /// Pushed routes hide the tab bar, so a user cannot switch tabs while any
    /// path is non-empty; the DEBUG-only launch argument seeds all four paths
    /// (including cartPath) and the labeled overlay switches tabs
    /// programmatically. Verifies: simultaneous non-empty paths, pushed-page
    /// identity and local state across switches for EVERY probe path
    /// (category/cart/me tick to 2, switch away, switch back, still 2), the
    /// home .cart route keeping its observable label across switches, and back
    /// popping only the current stack. This supplements — never replaces —
    /// TC-NAV-04, whose user-reachable scenario stays 未验证.
    @MainActor func testControlledSimultaneousPathsSwitchingAndBackScope() {
        let app = XCUIApplication()
        app.launchArguments += [
            "--uitest-nav-control",
            "--uitest-nav-paths",
            "home=cart;category=probe;cart=probe;me=probe",
        ]
        app.launch()
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

        // Back on category pops only this stack; home's path is untouched.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        app.buttons["navctl.select.home"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.fixture"].label, homeCartRouteLabel)

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

        // Me probe (mePath): same identity sequence, then pop every path.
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
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["me.pending"].waitForExistence(timeout: 5))
        app.buttons["navctl.select.cart"].tap()
        XCTAssertTrue(app.staticTexts["cart.probeIdentity"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.buttons["navctl.select.home"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openCart"].waitForExistence(timeout: 5))
    }

    @MainActor private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 10))
        return app
    }
}
