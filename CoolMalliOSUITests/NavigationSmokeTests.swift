import XCTest

final class NavigationSmokeTests: XCTestCase {
    @MainActor func testCatalogRouteOpensCartAndReturns() {
        let app = launchCatalog()
        app.buttons["catalog.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["catalog.openCart"].waitForExistence(timeout: 5))
    }

    @MainActor func testFeatureTabsSwitchAndReturn() {
        let app = launchCatalog()
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 5))
        app.tabBars.buttons["商品"].tap()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 5))
    }

    @MainActor private func launchCatalog() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["catalog.fixture"].waitForExistence(timeout: 10))
        return app
    }
}
