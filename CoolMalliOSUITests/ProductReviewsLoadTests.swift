import XCTest

final class ProductReviewsLoadTests: XCTestCase {
    @MainActor private func enter(_ mode: String = "valid", large: Bool = false) -> XCUIApplication
    {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-banner-manual", "--ui-product-detail-fixture",
            "valid",
            "--ui-product-reviews-fixture", mode,
        ]
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        let product = app.buttons["home.flashSale.830001.card"]
        for _ in 0..<5 { if product.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(product.isHittable); product.tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        let all = app.buttons["detail.reviews.all"]
        let appFrame = app.frame
        let top = app.buttons["detail.back"].frame.maxY + 8
        let bottom = app.buttons["客服"].frame.minY - 8
        let center = (top + bottom) / 2
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<6 {
            let frame = all.frame
            if all.isHittable && frame.minY >= top && frame.maxY <= bottom { break }
            let delta = frame.midY - center
            let start = delta >= 0 ? bottom - 16 : top + 16
            let end = min(bottom - 16, max(top + 16, start - delta))
            origin.withOffset(CGVector(dx: appFrame.midX, dy: start))
                .press(
                    forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: appFrame.midX, dy: end)))
        }
        XCTAssertTrue(all.isHittable)
        XCTAssertGreaterThanOrEqual(all.frame.minY, top)
        XCTAssertLessThanOrEqual(all.frame.maxY, bottom)
        all.tap()
        XCTAssertTrue(app.navigationBars["商品评价"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func list(_ app: XCUIApplication) -> XCUIElement {
        let list = app.descendants(matching: .any)["reviews.list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertEqual(list.value as? String, "商品ID：830001")
        return list
    }
    @MainActor private func find(_ id: String, _ app: XCUIApplication, upward: Bool = true)
        -> XCUIElement
    {
        let element = app.descendants(matching: .any)[id].firstMatch
        for _ in 0..<7 {
            if element.isHittable { break }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable); return element
    }
    @MainActor private func refresh(_ app: XCUIApplication) {
        // Real downward pull inside the list. The new/replaced body proves the callback ran.
        let frame = list(app).frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(
            CGVector(
                dx: frame.midX, dy: max(frame.minY, app.navigationBars.firstMatch.frame.maxY) + 70)
        )
        .press(
            forDuration: 0.1,
            thenDragTo: origin.withOffset(
                CGVector(
                    dx: frame.midX,
                    dy: max(frame.minY, app.navigationBars.firstMatch.frame.maxY) + 380)))
    }
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testActualDetailRouteRefreshAppendAndReturn() {
        let app = enter(); _ = list(app)
        XCTAssertTrue(app.staticTexts["121****50"].exists)
        XCTAssertTrue(app.staticTexts["2026-07-15 21:24:07"].firstMatch.exists)
        let first = app.descendants(matching: .any)["reviews.image.1.0"].firstMatch
        let second = app.descendants(matching: .any)["reviews.image.1.1"].firstMatch
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 1)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertLessThan(first.frame.maxX, second.frame.minX)
        screenshot(app, "reviews-default")
        refresh(app)
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "刷新后的评价"))
                .firstMatch.waitForExistence(timeout: 5))
        _ = find("reviews.card.4", app)
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "第三条更新"))
                .firstMatch.exists)
        XCTAssertTrue(find("reviews.exhausted", app).exists)
        screenshot(app, "reviews-last-page")
        app.buttons["reviews.back"].tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.reviews.all"].exists)
    }
    @MainActor func testInitialAndAppendFailureRetrySamePage() {
        let app = enter("append-retry"); _ = list(app)
        find("reviews.more.retry", app).tap()
        XCTAssertTrue(find("reviews.card.4", app).exists)
        XCTAssertTrue(find("reviews.exhausted", app).exists)
    }
    @MainActor func testInitialFailureRetriesActualPage() {
        let app = enter("retry")
        XCTAssertTrue(app.staticTexts["reviews.error"].waitForExistence(timeout: 5))
        app.buttons["reviews.retry"].tap(); _ = list(app)
        XCTAssertTrue(app.staticTexts["121****50"].exists)
    }
    @MainActor func testEmptyListPullRefreshesShortContent() {
        let app = enter("empty"); _ = list(app)
        XCTAssertTrue(app.staticTexts["reviews.empty"].exists)
        refresh(app)
        XCTAssertTrue(app.staticTexts["121****50"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["reviews.empty"].exists)
    }
    @MainActor func testRefreshFailureKeepsExistingReviews() {
        let app = enter("refresh-failure"); _ = list(app)
        refresh(app)
        _ = find("reviews.refresh.error", app)
        XCTAssertTrue(find("reviews.card.1", app, upward: false).exists)
        screenshot(app, "reviews-refresh-failure")
    }
    @MainActor func testLoadingReturnsToSameDetail() {
        let app = enter("loading")
        XCTAssertTrue(
            app.descendants(matching: .any)["reviews.loading"].firstMatch.waitForExistence(
                timeout: 5))
        app.buttons["reviews.back"].tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
    }
    @MainActor func testLargeTextReviewContentRemainsReachable() {
        let app = enter(large: true); _ = list(app)
        XCTAssertTrue(app.staticTexts["121****50"].exists)
        XCTAssertTrue(find("reviews.image.1.1", app).exists)
        screenshot(app, "reviews-accessibility")
    }
}
