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

    @MainActor func testEmptyFixtureShowsCountsAndRetryStaysEmpty() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "empty"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 10))
        // R-HOME-01-03: valid empty still exposes the observable counts.
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：0")
        XCTAssertEqual(app.staticTexts["home.count.coupon"].label, "优惠券：0")
        XCTAssertEqual(app.staticTexts["home.count.category"].label, "分类：0")
        XCTAssertEqual(app.staticTexts["home.count.flashSale"].label, "限时精选：0")
        XCTAssertEqual(app.staticTexts["home.count.recommend"].label, "推荐：0")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：0")
        XCTAssertEqual(app.staticTexts["home.count.categoryAll"].label, "完整分类（辅助）：0")
        app.buttons["home.retry"].tap()
        XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.retry"].exists)
    }

    @MainActor func testOnlyCategoryAllFixtureStaysEmptyWithObservableAuxiliaryCount() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "empty-category"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.source"].label, "工程夹具（empty-category）")
        // Six display arrays empty; only the auxiliary full-category count is
        // non-zero and observable (R-HOME-01-03).
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：0")
        XCTAssertEqual(app.staticTexts["home.count.coupon"].label, "优惠券：0")
        XCTAssertEqual(app.staticTexts["home.count.category"].label, "分类：0")
        XCTAssertEqual(app.staticTexts["home.count.flashSale"].label, "限时精选：0")
        XCTAssertEqual(app.staticTexts["home.count.recommend"].label, "推荐：0")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：0")
        XCTAssertEqual(app.staticTexts["home.count.categoryAll"].label, "完整分类（辅助）：3")
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

    /// R-HOME-01-04: a missing value, a flag-like next argument, or an unknown
    /// value must stop with the explicit test-configuration error — never fall
    /// through to the real HTTP service.
    @MainActor func testMissingOrUnknownFixtureValueStopsWithConfigError() {
        let cases: [[String]] = [
            ["--ui-home-fixture"],
            ["--ui-home-fixture", "--uitest-nav-fixture"],
            ["--ui-home-fixture", "bogus"],
        ]
        for arguments in cases {
            let app = XCUIApplication()
            app.launchArguments += arguments
            app.launch()
            XCTAssertTrue(
                app.staticTexts["home.testConfigError"].waitForExistence(timeout: 10),
                "expected config error for \(arguments)")
            XCTAssertFalse(app.staticTexts["home.loaded"].waitForExistence(timeout: 2))
            XCTAssertFalse(app.staticTexts["home.error"].waitForExistence(timeout: 2))
            app.terminate()
        }
    }
}
