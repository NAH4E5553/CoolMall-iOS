import XCTest

final class ProductDetailLoadTests: XCTestCase {
    @MainActor private func enter(_ mode: String = "valid", large: Bool = false) -> XCUIApplication
    {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-product-detail-fixture", mode,
            "--ui-banner-manual",
        ]
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        let card = app.buttons["home.flashSale.830001.card"]
        for _ in 0..<5 {
            if card.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        card.tap()
        return app
    }

    @MainActor private func loaded(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.scrollViews["detail.scroll"].value as? String, "商品ID：830001")
        XCTAssertFalse(app.staticTexts["detail.goodsID"].exists)
        XCTAssertFalse(app.buttons["detail.tick"].exists)
        XCTAssertFalse(app.tabBars.buttons["首页"].exists)
    }

    @MainActor private func openSpecifications(_ app: XCUIApplication) {
        let button = app.buttons["detail.openSpecifications"]
        for _ in 0..<3 {
            if button.isHittable { break }
            let frame = app.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            // Stay in the scrollable middle, above the fixed action bar at AX sizes.
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.height * 0.55))
                .press(
                    forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: frame.height * 0.25))
                )
        }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }

    @MainActor private func dismissSpecifications(_ app: XCUIApplication) {
        let frame = app.staticTexts["detail.spec.title"].frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: app.frame.midX, dy: frame.minY + 6))
            .press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 12))
            )
        XCTAssertTrue(app.staticTexts["detail.spec.title"].waitForNonExistence(timeout: 3))
    }

    @MainActor private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testRealHomeIDManualImagesAndReturn() {
        let app = enter()
        loaded(app)
        XCTAssertEqual(
            app.descendants(matching: .any)["detail.image.position"].value as? String, "1 / 2")
        app.descendants(matching: .any)["detail.images"].swipeLeft()
        XCTAssertEqual(
            app.descendants(matching: .any)["detail.image.position"].value as? String, "2 / 2")
        keepScreenshot(app, name: "detail-default")
        openSpecifications(app)
        XCTAssertTrue(app.buttons["detail.spec.1"].waitForExistence(timeout: 5))
        let frames = [1, 2, 3].map { app.buttons["detail.spec.\($0)"].frame }
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 1)
        XCTAssertEqual(frames[0].minY, frames[2].minY, accuracy: 1)
        XCTAssertEqual(frames[0].width, frames[1].width, accuracy: 1)
        XCTAssertLessThan(frames[0].midX, frames[1].midX)
        XCTAssertLessThan(frames[1].midX, frames[2].midX)
        keepScreenshot(app, name: "detail-spec-grid")
        dismissSpecifications(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)))
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].exists)
    }

    @MainActor func testSpecificationDraftPricesAndFreshPageReset() {
        let app = enter()
        loaded(app)
        openSpecifications(app)
        XCTAssertTrue(app.buttons["detail.spec.1"].waitForExistence(timeout: 5))
        app.buttons["detail.spec.1"].tap()
        app.buttons["detail.spec.plus"].tap()
        XCTAssertEqual(app.staticTexts["detail.spec.quantity"].label, "2")
        XCTAssertFalse(app.buttons["detail.spec.plus"].isEnabled)
        app.buttons["detail.spec.layout"].tap()
        XCTAssertTrue(app.buttons["detail.spec.1"].isSelected)
        keepScreenshot(app, name: "detail-spec-selected")
        dismissSpecifications(app)
        openSpecifications(app)
        XCTAssertTrue(app.buttons["detail.spec.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.spec.1"].isSelected)
        XCTAssertEqual(app.staticTexts["detail.spec.quantity"].label, "2")
        app.buttons["detail.spec.3"].tap()
        let selectedPrice = app.descendants(matching: .any)["detail.spec.price"].label
        dismissSpecifications(app)
        XCTAssertEqual(app.descendants(matching: .any)["detail.price"].label, selectedPrice)
        openSpecifications(app)
        app.buttons["detail.spec.3"].tap()
        XCTAssertEqual(app.staticTexts["detail.spec.selection"].label, "请选择规格")
        let basePrice = app.descendants(matching: .any)["detail.spec.price"].label
        dismissSpecifications(app)
        XCTAssertEqual(app.descendants(matching: .any)["detail.price"].label, basePrice)
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].exists)
        XCTAssertTrue(app.buttons["home.flashSale.830001.card"].isHittable)
        app.buttons["home.flashSale.830001.card"].tap()
        loaded(app)
        openSpecifications(app)
        XCTAssertTrue(app.buttons["detail.spec.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.spec.1"].isSelected)
        XCTAssertEqual(app.staticTexts["detail.spec.quantity"].label, "1")
    }

    @MainActor func testDetailErrorRetryUsesRealEntry() {
        let app = enter("retry")
        XCTAssertTrue(app.staticTexts["detail.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["detail.loaded"].exists)
        app.buttons["detail.retry"].tap()
        loaded(app)
    }

    @MainActor func testSpecificationErrorRetryRetainsMainProduct() {
        let app = enter("spec-retry")
        loaded(app); openSpecifications(app)
        XCTAssertTrue(app.staticTexts["detail.spec.error"].waitForExistence(timeout: 5))
        app.buttons["detail.spec.retry"].tap()
        XCTAssertTrue(app.buttons["detail.spec.2"].waitForExistence(timeout: 5))
        app.buttons["detail.spec.2"].tap()
        XCTAssertEqual(app.staticTexts["detail.spec.stock"].label, "库存：0")
        XCTAssertFalse(app.buttons["detail.spec.plus"].isEnabled)
        keepScreenshot(app, name: "detail-spec-error-recovered")
        dismissSpecifications(app)
        XCTAssertTrue(app.staticTexts["detail.loaded"].exists)
    }

    @MainActor func testEmptySpecificationsRemainEmpty() {
        let app = enter("empty-specs")
        loaded(app); openSpecifications(app)
        XCTAssertTrue(app.staticTexts["detail.spec.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.spec.plus"].isEnabled)
        XCTAssertFalse(app.buttons["detail.spec.1"].exists)
    }

    @MainActor func testUnavailableProductCannotOpenSpecifications() {
        let app = enter("unavailable")
        loaded(app)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["detail.unavailable"].exists)
        XCTAssertFalse(app.buttons["detail.openSpecifications"].isEnabled)
    }

    @MainActor func testLoadingCanReturnToUnchangedHome() {
        let app = enter("loading")
        XCTAssertTrue(
            app.descendants(matching: .any)["detail.loading"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].exists)
    }

    @MainActor func testAccessibilitySpecificationControlsRemainReachable() {
        let app = enter(large: true)
        loaded(app); openSpecifications(app)
        XCTAssertTrue(app.buttons["detail.spec.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.spec.1"].isHittable)
        app.buttons["detail.spec.1"].tap()
        XCTAssertTrue(app.buttons["detail.spec.plus"].isHittable)
        app.buttons["detail.spec.plus"].tap()
        XCTAssertEqual(app.staticTexts["detail.spec.quantity"].label, "2")
        keepScreenshot(app, name: "detail-accessibility-spec")
        XCTAssertTrue(app.staticTexts["detail.spec.title"].isHittable)
        dismissSpecifications(app)
    }
    @MainActor func testCouponRulesExpandCollapseAndOutsideDismiss() {
        let app = enter(); loaded(app)
        let coupon = app.buttons["detail.coupon.860001"]
        for _ in 0..<4 { if coupon.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(coupon.isHittable); coupon.tap()
        let rules = app.buttons["detail.coupon.rules.860001"]
        XCTAssertTrue(rules.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["detail.coupon.description.860001"].exists)
        rules.tap()
        XCTAssertEqual(app.staticTexts["detail.coupon.description.860001"].label, "小米商城精选商品可用")
        keepScreenshot(app, name: "detail-coupon-rules")
        rules.tap()
        XCTAssertFalse(app.staticTexts["detail.coupon.description.860001"].exists)
        // Real outside tap, above the bottom overlay, must dismiss it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.16)).tap()
        XCTAssertTrue(rules.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["detail.openSpecifications"].isHittable)
    }

    @MainActor func testReviewLimitDeliveryAndContinuousDetailImages() {
        let app = enter(); loaded(app)
        let first = app.descendants(matching: .any)["detail.contentImage.0"].firstMatch
        let second = app.descendants(matching: .any)["detail.contentImage.1"].firstMatch
        for _ in 0..<6 { if first.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(first.exists); XCTAssertTrue(second.exists)
        XCTAssertEqual(first.frame.maxY, second.frame.minY, accuracy: 0.5)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 0.5)
        XCTAssertTrue(app.staticTexts["评价内容1"].exists)
        XCTAssertTrue(app.staticTexts["评价内容2"].exists)
        let stars = app.descendants(matching: .any)["detail.review.stars.2"].firstMatch
        XCTAssertEqual(stars.label, "4星")
        XCTAssertFalse(app.staticTexts["评价内容3"].exists)
        XCTAssertTrue(app.staticTexts["北京市 北平"].exists)
        keepScreenshot(app, name: "detail-continuous-images")
    }

}
