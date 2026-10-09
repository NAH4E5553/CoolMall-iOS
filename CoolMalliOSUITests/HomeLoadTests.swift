import XCTest

/// HOME-01 UI checks over the DEBUG deterministic home fixture modes
/// (AT-HOME-01-11 home scenarios). The real-HTTP integration evidence for
/// AT-12 is collected separately from the same gate build via a plain
/// no-argument launch.
final class HomeLoadTests: XCTestCase {
    @MainActor func testValidFixtureShowsLoadedStateAndSectionCounts() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "valid"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：6")
        XCTAssertEqual(app.staticTexts["home.count.coupon"].label, "优惠券：3")
        XCTAssertEqual(app.staticTexts["home.count.category"].label, "分类：10")
        XCTAssertEqual(app.staticTexts["home.count.flashSale"].label, "限时精选：8")
        XCTAssertEqual(app.staticTexts["home.count.recommend"].label, "推荐：8")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        XCTAssertEqual(app.staticTexts["home.count.categoryAll"].label, "完整分类（辅助）：43")
        XCTAssertEqual(app.staticTexts["home.source"].label, "工程夹具（valid）")
        // Four tabs remain reachable around the minimal read UI.
        XCTAssertTrue(app.tabBars.buttons["首页"].exists)
    }

    @MainActor func testEmptyFixtureShowsEmptyAndRetryStaysEmpty() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "empty"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 10))
        app.buttons["home.retry"].tap()
        XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.retry"].exists)
    }

    @MainActor func testRetryFixtureFailsFirstReadThenSucceedsOnUserRetry() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "retry"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.error"].waitForExistence(timeout: 10))
        app.buttons["home.retry"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.count.flashSale"].label, "限时精选：1")
    }

    @MainActor func testConflictingTestArgumentsStopWithConfigError() {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-nav-fixture", "--ui-home-fixture", "valid"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.testConfigError"].waitForExistence(timeout: 10))
        // No read indicator appears: the read is stopped, not guessed.
        XCTAssertFalse(app.staticTexts["home.loaded"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["home.error"].waitForExistence(timeout: 2))
    }
}
