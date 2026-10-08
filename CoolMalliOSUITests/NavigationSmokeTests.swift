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

    @MainActor private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 10))
        return app
    }
}
