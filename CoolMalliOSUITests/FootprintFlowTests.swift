import XCTest

final class FootprintFlowTests: XCTestCase {
    @MainActor private func app(seed: Bool = false, failure: String? = nil, large: Bool = false)
        -> XCUIApplication
    {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-banner-manual", "--ui-product-detail-fixture",
            "valid", "--ui-cart-store", UUID().uuidString, "--ui-account-fixture", "success",
        ]
        if seed { app.launchArguments += ["--ui-footprints-seed"] }
        if let failure { app.launchArguments += ["--ui-footprints-failure", failure] }
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch(); return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name;
        a.lifetime = .keepAlways; add(a)
    }
    @MainActor private func openAll(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10));
        app.tabBars.buttons["我的"].tap()
        let all = app.buttons["me.footprints.all"]
        for _ in 0..<4 { if all.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(all.isHittable); all.tap()
        XCTAssertTrue(app.buttons["footprints.clear"].waitForExistence(timeout: 5))
    }
    @MainActor private func refresh(_ app: XCUIApplication) {
        let scroll = app.scrollViews["footprints.page"]
        let frame = scroll.frame.intersection(app.frame)
        var contentTop = max(frame.minY, app.navigationBars.firstMatch.frame.maxY)
        let retry = app.buttons["footprints.retry"]
        if retry.exists { contentTop = max(contentTop, retry.frame.maxY + 12) }
        let bottom = frame.maxY - 44
        XCTAssertGreaterThan(bottom - contentTop, 100)
        let start = CGPoint(x: frame.midX, y: contentTop + (bottom - contentTop) * 0.2)
        let end = CGPoint(x: frame.midX, y: contentTop + (bottom - contentTop) * 0.85)
        let attachment = XCTAttachment(
            string: "scroll=\(frame); contentTop=\(contentTop); start=\(start); end=\(end)")
        attachment.name = "footprints-pull-geometry"; attachment.lifetime = .keepAlways;
        add(attachment)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: start.x, dy: start.y)).press(
            forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)))
    }
    @MainActor func testDetailRecordsPreviewAllAndScopedClearSurvivesRestart() {
        let app = app()
        let card = app.buttons["home.flashSale.830001.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        for _ in 0..<5 { if card.isHittable { break }; app.swipeUp() }
        card.tap(); XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5));
        app.buttons["detail.back"].tap()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.footprint.830001"].waitForExistence(timeout: 5));
        capture(app, "me-recent-footprints")
        app.buttons["me.footprints.all"].tap()
        XCTAssertTrue(app.buttons["footprints.item.830001"].waitForExistence(timeout: 5));
        capture(app, "footprints-detail-record")
        app.buttons["footprints.clear"].tap()
        app.sheets["清空全部足迹？"].buttons.matching(identifier: "footprints.confirmClear").firstMatch
            .tap()
        XCTAssertTrue(app.staticTexts["footprints.empty"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); openAll(app)
        XCTAssertTrue(app.staticTexts["footprints.empty"].waitForExistence(timeout: 5))
    }
    @MainActor func testLocalPaginationAppendFailureRetriesAndOpensRealDetail() {
        let app = app(seed: true, failure: "append"); openAll(app)
        XCTAssertTrue(app.buttons["footprints.item.830025"].waitForExistence(timeout: 5))
        capture(app, "footprints-grid")
        let more = app.buttons["footprints.more"]
        for _ in 0..<12 { if more.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        XCTAssertTrue(app.staticTexts["加载更多失败，点击重试"].waitForExistence(timeout: 5)); more.tap()
        let last = app.buttons["footprints.item.830001"]
        for _ in 0..<5 { if last.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(last.isHittable); capture(app, "footprints-paged-tail"); last.tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5));
        XCTAssertTrue(app.staticTexts["detail.loaded"].label.contains("830001"))
        app.buttons["detail.back"].tap();
        XCTAssertTrue(app.buttons["footprints.item.830001"].waitForExistence(timeout: 5))
    }
    @MainActor func testPullRefreshPreservesHistoryOnFailureAndRetries() {
        let app = app(seed: true, failure: "refresh"); openAll(app)
        XCTAssertTrue(app.buttons["footprints.item.830025"].waitForExistence(timeout: 5));
        refresh(app)
        XCTAssertTrue(app.staticTexts["足迹刷新失败，原记录保留，请重试"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["footprints.item.830025"].exists);
        XCTAssertTrue(app.buttons["重试"].isHittable)
        capture(app, "footprints-refresh-failure")
        refresh(app)
        XCTAssertTrue(app.staticTexts["足迹刷新失败，原记录保留，请重试"].waitForNonExistence(timeout: 5));
        XCTAssertTrue(app.buttons["footprints.item.830025"].exists)
    }
    @MainActor func testRefreshFailureRemainsReachableWhileBrowsingHistory() {
        let app = app(seed: true, failure: "refresh"); openAll(app)
        XCTAssertTrue(app.buttons["footprints.item.830025"].waitForExistence(timeout: 5))
        refresh(app)
        let error = app.staticTexts["足迹刷新失败，原记录保留，请重试"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let first = app.buttons["footprints.item.830025"]
        let beforeY = first.frame.minY
        app.swipeUp()
        XCTAssertTrue(!first.exists || first.frame.minY < beforeY - 40)
        XCTAssertTrue(error.exists)
        XCTAssertTrue(app.buttons["footprints.retry"].isHittable)
        capture(app, "footprints-refresh-failure-scrolled")
        app.buttons["重试"].tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["footprints.clear"].label.contains("25"))
    }
    @MainActor func testLargeTextRefreshFailureRemainsReachable() {
        let app = app(seed: true, failure: "refresh", large: true); openAll(app)
        XCTAssertTrue(app.buttons["footprints.item.830025"].waitForExistence(timeout: 5))
        refresh(app)
        let error = app.staticTexts["足迹刷新失败，原记录保留，请重试"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["footprints.retry"].isHittable)
        capture(app, "footprints-large-refresh-failure")
        app.buttons["footprints.retry"].tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["footprints.item.830025"].exists)
    }
    @MainActor func testEmptyHistoryPullRefreshAndRetry() {
        let app = app(failure: "refresh"); openAll(app)
        XCTAssertTrue(app.staticTexts["footprints.empty"].waitForExistence(timeout: 5));
        refresh(app)
        XCTAssertTrue(app.staticTexts["足迹刷新失败，原记录保留，请重试"].waitForExistence(timeout: 5))
        app.buttons["重试"].tap()
        XCTAssertTrue(app.staticTexts["足迹刷新失败，原记录保留，请重试"].waitForNonExistence(timeout: 5));
        XCTAssertTrue(app.staticTexts["footprints.empty"].exists)
        capture(app, "footprints-empty-refreshed")
    }
    @MainActor func testLoginAndLogoutKeepGuestHistorySeparate() {
        let app = app(seed: true)
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.footprint.830025"].waitForExistence(timeout: 5))
        app.buttons["me.account"].tap(); app.buttons["login.choosePassword"].tap()
        app.textFields["login.phone"].tap(); app.textFields["login.phone"].typeText("13800000000")
        app.secureTextFields["login.password"].tap();
        app.secureTextFields["login.password"].typeText("test-only")
        if app.toolbars.buttons["完成"].exists { app.toolbars.buttons["完成"].tap() }
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.staticTexts["me.footprints.empty"].waitForExistence(timeout: 5))
        app.buttons["me.account"].tap()
        let logout = app.buttons["profile.logout"]
        for _ in 0..<3 { if logout.isHittable { break }; app.swipeUp() }
        logout.tap();
        app.sheets["退出当前账号？"].buttons.matching(identifier: "profile.confirmLogout").firstMatch.tap()
        XCTAssertTrue(app.buttons["me.footprint.830025"].waitForExistence(timeout: 5));
        capture(app, "guest-footprints-restored")
    }
    @MainActor func testLargeTextFootprintsRemainReachable() {
        let app = app(seed: true, large: true); openAll(app)
        XCTAssertTrue(app.buttons["footprints.item.830025"].waitForExistence(timeout: 5));
        capture(app, "footprints-large")
        XCTAssertTrue(app.buttons["footprints.clear"].isHittable)
    }
}
