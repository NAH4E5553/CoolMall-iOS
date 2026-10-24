import XCTest

final class ShoppingCartFlowTests: XCTestCase {
    @MainActor private func app(
        _ token: String, seed: Bool = false, large: Bool = false, detailMode: String = "valid"
    )
        -> XCUIApplication
    {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-banner-manual",
            "--ui-product-detail-fixture", detailMode, "--ui-cart-store", token,
        ]
        if seed { app.launchArguments.append("--ui-cart-seed") }
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch(); return app
    }
    @MainActor private func enterDetail(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        let card = app.buttons["home.flashSale.830001.card"]
        for _ in 0..<5 { if card.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(card.isHittable); card.tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name;
        image.lifetime = .keepAlways; add(image)
    }
    @MainActor func testDetailAddIndependentCartReturnsToOriginalDetail() {
        let app = app(UUID().uuidString)
        enterDetail(app)
        app.buttons["detail.addCart"].tap()
        XCTAssertTrue(app.buttons["detail.spec.1"].waitForExistence(timeout: 5))
        app.buttons["detail.spec.1"].tap()
        app.buttons["detail.spec.addCart"].tap()
        XCTAssertTrue(app.staticTexts["detail.cart.message"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.cart.message"].label, "已加入购物车")
        XCTAssertFalse(app.staticTexts["detail.spec.title"].exists)
        app.buttons["detail.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.1"].label, "1")
        XCTAssertFalse(app.tabBars.buttons["首页"].exists)
        capture(app, "cart-independent")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        let specification = app.buttons["detail.openSpecifications"]
        for _ in 0..<3 { if specification.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(specification.label.contains("黑色"))
        app.buttons["detail.addCart"].tap()
        XCTAssertTrue(app.staticTexts["detail.cart.message"].waitForExistence(timeout: 5))
        // A second distinct click after completion is a second actual addition.
        app.buttons["detail.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.1"].label, "2")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["detail.back"].tap()
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.1"].label, "2")
        XCTAssertTrue(app.tabBars.buttons["首页"].exists)
    }
    @MainActor func testPriceReturnsToOriginalStillPresentsSecondConfirmation() {
        let app = app(UUID().uuidString, detailMode: "cart-price-return")
        enterDetail(app)
        app.buttons["detail.addCart"].tap()
        XCTAssertTrue(app.buttons["detail.spec.1"].waitForExistence(timeout: 5))
        app.buttons["detail.spec.1"].tap()
        app.buttons["detail.spec.addCart"].tap()
        let alert = app.alerts["商品价格变化"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(
            alert.staticTexts.matching(NSPredicate(format: "label CONTAINS '4,099'")).firstMatch
                .exists)
        alert.buttons.matching(identifier: "detail.cart.confirmPrice").firstMatch.tap()
        let returned = app.alerts.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '刚确认' AND label CONTAINS '3,999'")
        ).firstMatch
        XCTAssertTrue(returned.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["detail.cart.message"].exists)
        capture(app, "cart-returned-price-reconfirmation")
        alert.buttons.matching(identifier: "detail.cart.confirmPrice").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["detail.cart.message"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.cart.message"].label, "已加入购物车")
        app.buttons["detail.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.1"].label, "1")
        XCTAssertEqual(app.staticTexts["cart.price.830001.1"].label, "¥3,999.00")
    }
    @MainActor func testKnownZeroStockDisablesSheetAndDetailAdd() {
        let app = app(UUID().uuidString)
        enterDetail(app); app.buttons["detail.addCart"].tap()
        XCTAssertTrue(app.buttons["detail.spec.2"].waitForExistence(timeout: 5))
        app.buttons["detail.spec.2"].tap()
        XCTAssertEqual(app.staticTexts["detail.spec.stock"].label, "库存：0")
        XCTAssertFalse(app.buttons["detail.spec.addCart"].isEnabled)
        let title = app.staticTexts["detail.spec.title"].frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: app.frame.midX, dy: title.minY + 6))
            .press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 12))
            )
        XCTAssertTrue(app.staticTexts["detail.spec.title"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.addCart"].isEnabled)
        XCTAssertFalse(app.staticTexts["detail.cart.message"].exists)
        app.buttons["detail.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.empty"].waitForExistence(timeout: 5))
    }
    @MainActor func testPendingQuantityKeepsControlsStableWithoutProcessingLabel() {
        let app = app(UUID().uuidString, seed: true, detailMode: "cart-processing")
        app.tabBars.buttons["购物车"].tap()
        let quantity = app.staticTexts["cart.quantity.830001.1"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        app.buttons["cart.select.830001.1"].tap()
        let current = app.buttons["cart.plus.830001.1"]
        let peer = app.buttons["cart.plus.830001.3"]
        XCTAssertTrue(current.isEnabled); XCTAssertTrue(peer.isEnabled)
        XCTAssertFalse(app.buttons["cart.minus.830001.1"].isEnabled)
        XCTAssertTrue(app.buttons["cart.edit"].isEnabled)
        XCTAssertTrue(app.buttons["cart.checkout"].isEnabled)
        let initialFrame = current.frame
        current.tap()
        XCTAssertTrue(current.isEnabled)
        XCTAssertTrue(peer.isEnabled)
        XCTAssertTrue(app.buttons["cart.edit"].isEnabled)
        XCTAssertTrue(app.buttons["cart.checkout"].isEnabled)
        XCTAssertEqual(quantity.label, "1")
        XCTAssertFalse(app.staticTexts["处理中"].exists)
        XCTAssertFalse(app.staticTexts["cart.processing.830001.1"].exists)
        XCTAssertFalse(app.staticTexts["cart.processing.830001.3"].exists)
        XCTAssertEqual(current.frame, initialFrame)
        // The button stays enabled visually; the existing owner rejects a
        // second tap while the first real verifier request is held.
        current.tap()
        XCTAssertFalse(app.staticTexts["cart.message"].exists)
        XCTAssertEqual(quantity.label, "1")
        capture(app, "cart-pending-quantity-controls-stable-no-processing-label")
        app.buttons["cart.fixture.releaseIncrease"].tap()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label == '2'"), object: quantity)
                ], timeout: 10),
            .completed)
        XCTAssertTrue(current.isEnabled); XCTAssertTrue(peer.isEnabled)
        XCTAssertTrue(app.buttons["cart.minus.830001.1"].isEnabled)
        XCTAssertFalse(app.staticTexts["处理中"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["cart.total"].label.contains("7,998"))
    }
    @MainActor func testTabReturnVerificationKeepsValidRowGeometryStable() {
        let app = app(UUID().uuidString, seed: true, detailMode: "cart-processing")
        app.tabBars.buttons["购物车"].tap()
        let select = app.buttons["cart.select.830001.1"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "enabled == YES"), object: select)
                ], timeout: 5),
            .completed)
        let first = app.descendants(matching: .any)["cart.line.830001.1"]
        let second = app.descendants(matching: .any)["cart.line.830001.3"]
        let originalFirst = first.frame, originalSecond = second.frame
        app.tabBars.buttons["首页"].tap()
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        // Existing fixture read 3 holds real entry verification on this return.
        // Unknown stock must still prevent selection; no layout-only fake state.
        XCTAssertFalse(select.isEnabled)
        let heldFirst = first.frame, heldSecond = second.frame
        let heldNote = app.buttons["cart.status.830001.1"].exists
        capture(app, "cart-tab-return-entry-check-held")
        app.buttons["cart.fixture.releaseIncrease"].tap()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "enabled == YES"), object: select)
                ], timeout: 5),
            .completed)
        let settledFirst = first.frame, settledSecond = second.frame
        capture(app, "cart-tab-return-entry-check-complete")
        let geometry = XCTAttachment(
            string:
                "originalFirst=\(originalFirst); heldFirst=\(heldFirst); settledFirst=\(settledFirst); originalSecond=\(originalSecond); heldSecond=\(heldSecond); settledSecond=\(settledSecond); heldNote=\(heldNote)"
        )
        geometry.name = "entry-verification-row-geometry"; geometry.lifetime = .keepAlways
        add(geometry)
        XCTAssertEqual(heldFirst.height, settledFirst.height)
        XCTAssertEqual(heldSecond.minY, settledSecond.minY)
        XCTAssertEqual(originalFirst, settledFirst)
        XCTAssertEqual(originalSecond, settledSecond)
        XCTAssertFalse(heldNote)
        XCTAssertFalse(app.buttons["cart.status.830001.1"].exists)
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.1"].label, "1")
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.3"].label, "1")
    }
    @MainActor func testTabSelectionQuantityDeleteAndActualAppRestart() {
        let token = UUID().uuidString
        let app = app(token, seed: true)
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "cart.product.830001").count, 1)
        XCTAssertFalse(app.buttons["cart.minus.830001.1"].isEnabled)
        app.buttons["cart.plus.830001.1"].tap()
        let quantity = app.staticTexts["cart.quantity.830001.1"]
        XCTAssertTrue(
            NSPredicate(format: "label == '2'").evaluate(with: quantity)
                || XCTWaiter.wait(
                    for: [
                        XCTNSPredicateExpectation(
                            predicate: NSPredicate(format: "label == '2'"), object: quantity)
                    ], timeout: 5) == .completed
        )
        app.buttons["cart.selectAll"].tap()
        XCTAssertEqual(app.buttons["cart.checkout"].label, "结算(2)")
        XCTAssertTrue(app.descendants(matching: .any)["cart.total"].label.contains("12,097"))
        capture(app, "cart-tab-selected")
        app.buttons["cart.edit"].tap()
        app.buttons["cart.select.830001.3"].tap()
        app.buttons["cart.delete"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.3"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.1"].label, "2")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-cart-seed" }
        app.launch()
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.1"].label, "2")
        XCTAssertFalse(app.staticTexts["cart.quantity.830001.3"].exists)
        XCTAssertFalse(app.buttons["cart.checkout"].isEnabled)
        capture(app, "cart-disk-restored")
    }
    @MainActor private func dragVisibleContent(
        _ app: XCUIApplication, scroll: XCUIElement, upward: Bool
    ) {
        // The scroll view AX frame includes the safeAreaInset region. Default
        // swipeUp starts under the fixed summary at AX sizes, so intersect with
        // the actually unobscured content before synthesizing a real drag.
        let frame = scroll.frame.intersection(app.frame)
        let top = frame.minY + 12
        let bottom = min(frame.maxY, app.buttons["cart.selectAll"].frame.minY) - 12
        XCTAssertGreaterThan(bottom - top, 60)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let high = top + (bottom - top) * 0.2
        let low = top + (bottom - top) * 0.8
        origin.withOffset(CGVector(dx: frame.midX, dy: upward ? low : high))
            .press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: upward ? high : low)))
    }
    @MainActor func testLargeTypePendingQuantityKeepsControlsStableWithoutProcessingLabel() {
        let app = app(UUID().uuidString, seed: true, large: true, detailMode: "cart-processing")
        app.tabBars.buttons["购物车"].tap()
        let quantity = app.staticTexts["cart.quantity.830001.1"]
        let scroll = app.scrollViews["cart.scroll"], plus = app.buttons["cart.plus.830001.1"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if plus.exists && quantity.exists && plus.isHittable
                && plus.frame.maxY <= app.buttons["cart.selectAll"].frame.minY
            {
                break
            }
            dragVisibleContent(app, scroll: scroll, upward: true)
        }
        XCTAssertTrue(plus.isHittable)
        let initialFrame = plus.frame
        plus.tap()
        XCTAssertTrue(plus.isEnabled)
        XCTAssertFalse(app.staticTexts["处理中"].exists)
        XCTAssertFalse(app.staticTexts["cart.processing.830001.1"].exists)
        XCTAssertEqual(plus.frame, initialFrame)
        XCTAssertEqual(quantity.label, "1")
        plus.tap()
        XCTAssertEqual(quantity.label, "1")
        capture(app, "cart-accessibility-pending-controls-stable-no-processing-label")
        app.buttons["cart.fixture.releaseIncrease"].tap()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label == '2'"), object: quantity)
                ], timeout: 10),
            .completed)
        XCTAssertTrue(plus.isEnabled)
        XCTAssertFalse(app.staticTexts["处理中"].exists)
    }
    @MainActor func testLargeTypeBottomControlsAndProductNavigation() {
        let app = app(UUID().uuidString, seed: true, large: true)
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        let scroll = app.scrollViews["cart.scroll"]
        for _ in 0..<3 {
            let target = app.buttons["cart.minus.830001.3"]
            if target.isHittable && target.frame.maxY <= app.buttons["cart.selectAll"].frame.minY {
                break
            }
            dragVisibleContent(app, scroll: scroll, upward: true)
        }
        XCTAssertTrue(app.buttons["cart.minus.830001.3"].isHittable)
        XCTAssertTrue(app.buttons["cart.selectAll"].isHittable)
        XCTAssertLessThanOrEqual(
            app.buttons["cart.minus.830001.3"].frame.maxY, app.buttons["cart.selectAll"].frame.minY)
        capture(app, "cart-accessibility-last-row")
        for _ in 0..<3 {
            let header = app.buttons["cart.product.830001"]
            if header.isHittable && header.frame.minY >= scroll.frame.minY { break }
            dragVisibleContent(app, scroll: scroll, upward: false)
        }
        app.buttons["cart.product.830001"].tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["购物车"].exists)
    }
}
