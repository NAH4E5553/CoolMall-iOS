import XCTest

final class OrderCheckoutFlowTests: XCTestCase {
    @MainActor private func launch(
        _ mode: String = "success", guest: Bool = false, large: Bool = false
    ) -> XCUIApplication {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Synthetic login password prompt") { alert in
            let password = alert.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Save Password", "保存密码")
            ).firstMatch
            guard password.exists else { return false }
            for label in ["以后", "Not Now"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-banner-manual", "--ui-product-detail-fixture",
            "valid", "--ui-account-fixture", "success", "--ui-orders", mode, "--ui-addresses",
            "success", "--ui-cart-store", UUID().uuidString,
        ]
        if !guest { app.launchArguments += ["--ui-orders-signed-in"] }
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch(); XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func orders(_ app: XCUIApplication) {
        app.tabBars.buttons["我的"].tap(); app.buttons["me.orders.all"].tap()
    }
    @MainActor private func buy(
        _ app: XCUIApplication, quantity: Int = 2, repeated: Bool = false
    ) {
        let card = app.buttons["home.flashSale.830001.card"]
        for _ in 0..<5 { if card.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(card.isHittable); card.tap()
        let buy = app.buttons["detail.buyNow"]; XCTAssertTrue(buy.waitForExistence(timeout: 5));
        buy.tap()
        let sku = app.buttons["detail.spec.1"]; XCTAssertTrue(sku.waitForExistence(timeout: 5));
        sku.tap()
        if quantity == 2 { app.buttons["detail.spec.plus"].tap() }
        XCTAssertEqual(app.staticTexts["detail.spec.quantity"].label, String(quantity))
        if repeated {
            app.buttons["detail.spec.buyNow"].doubleTap()
        } else {
            app.buttons["detail.spec.buyNow"].tap()
        }
    }
    @MainActor private func login(_ app: XCUIApplication) {
        let choose = app.buttons["login.choosePassword"];
        XCTAssertTrue(choose.waitForExistence(timeout: 5)); choose.tap()
        let phone = app.textFields["login.phone"]; phone.tap(); phone.typeText("13800000000")
        let secret = app.secureTextFields["login.password"]; secret.tap();
        secret.typeText("test-only")
        if app.toolbars.buttons["完成"].exists { app.toolbars.buttons["完成"].tap() }
        app.buttons["login.submit"].tap()
    }
    @MainActor private func node(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name;
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testReadOnlyOrdersFiltersDetailsAndBackPreserveSource() {
        let app = launch(); orders(app)
        let first = app.buttons["orders.item.910001"];
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        XCTAssertTrue(app.staticTexts["order.status"].waitForExistence(timeout: 5));
        XCTAssertEqual(app.staticTexts["order.status"].label, "待付款")
        XCTAssertTrue(
            app.scrollViews["order.detail"].staticTexts.matching(
                NSPredicate(format: "label ENDSWITH %@", "TEST-910001")
            ).firstMatch.exists)
        for label in ["确认收货", "申请退款"] { XCTAssertFalse(app.buttons[label].exists) }
        capture(app, "order-readonly-detail"); app.navigationBars.buttons.firstMatch.tap()
        let filter = app.buttons["orders.filter.unevaluated"]
        let filters = app.scrollViews["orders.filters"]
        for _ in 0..<4 {
            let frame = filter.frame
            if frame.width > 0, filters.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                break
            }
            // The scroll view AX frame includes the navigation safe area. Drag through
            // the actual filter row, not that frame's center underneath the navigation bar.
            let rowY = frame.midY - filters.frame.minY
            let start = filters.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: filters.frame.width * 0.85, dy: rowY))
            let end = filters.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: filters.frame.width * 0.15, dy: rowY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(filters.frame.contains(CGPoint(x: filter.frame.midX, y: filter.frame.midY)))
        XCTAssertTrue(filter.isHittable); filter.tap()
        XCTAssertTrue(app.buttons["orders.item.910004"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["orders.item.910001"].exists)
        capture(app, "order-filter-unevaluated")
    }
    @MainActor func testOrderInitialFailureExplicitRetry() {
        let app = launch("failure"); orders(app)
        let retry = app.buttons["orders.retry"]; XCTAssertTrue(retry.waitForExistence(timeout: 5));
        retry.tap()
        XCTAssertTrue(app.buttons["orders.item.910001"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["orders.error"].exists);
        capture(app, "orders-retry-recovered")
    }
    @MainActor func testOrderAppendFailureKeepsRowsAndRetriesSamePage() {
        let app = launch("appendFailure"); orders(app)
        XCTAssertTrue(app.buttons["orders.item.910001"].waitForExistence(timeout: 5))
        let retry = app.buttons["orders.retry"]
        for _ in 0..<12 { if retry.exists { break }; app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); capture(app, "orders-append-failure")
        retry.tap(); XCTAssertTrue(app.buttons["orders.item.910011"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
    }
    @MainActor func testEmptyOrdersAndGuestEntryCanCancelWithoutRequestingOrder() {
        let app = launch("empty"); orders(app)
        XCTAssertTrue(node(app, "orders.empty").waitForExistence(timeout: 5));
        capture(app, "orders-empty")
        app.terminate()
        let guest = launch(guest: true); orders(guest)
        XCTAssertTrue(guest.buttons["login.choosePassword"].waitForExistence(timeout: 5))
        guest.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(guest.buttons["me.orders.all"].waitForExistence(timeout: 5))
    }
    @MainActor func testBuyNowGuestCancelThenLoginResumesSameSkuAndQuantity() {
        let app = launch(guest: true); buy(app)
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.buyNow"].waitForExistence(timeout: 5));
        app.buttons["detail.buyNow"].tap()
        login(app)
        XCTAssertTrue(app.staticTexts["checkout.quantity"].waitForExistence(timeout: 5))
        // Dismiss only the known AutoFill prompt if it arrived after navigation.
        for surface in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            if surface.buttons["以后"].exists
                && surface.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "保存密码"))
                    .firstMatch.exists
            {
                surface.buttons["以后"].tap()
            }
        }
        XCTAssertEqual(app.staticTexts["checkout.quantity"].label, "数量：2")
        XCTAssertTrue(
            node(app, "checkout.subtotal").label.contains("7,998")
                || node(app, "checkout.subtotal").label.contains("7998"))
        XCTAssertTrue(app.buttons["checkout.submit"].exists);
        XCTAssertFalse(app.buttons["去支付"].exists)
        capture(app, "checkout-guest-login-resumed")
    }
    @MainActor func testCheckoutAddressCouponAndBackKeepSubtotalAndDetailSelection() {
        let app = launch(); buy(app)
        let quantity = app.staticTexts["checkout.quantity"];
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        let subtotal = node(app, "checkout.subtotal").label
        app.buttons["checkout.address"].tap()
        let address = app.buttons["addresses.card.2"];
        XCTAssertTrue(address.waitForExistence(timeout: 5)); address.tap()
        XCTAssertTrue(app.buttons["checkout.address"].waitForExistence(timeout: 5));
        XCTAssertTrue(app.buttons["checkout.address"].label.contains("联系人2"))
        app.buttons["checkout.coupons"].tap(); app.buttons["checkout.coupon.701"].tap()
        XCTAssertTrue(app.buttons["checkout.coupons"].waitForExistence(timeout: 5));
        XCTAssertTrue(app.buttons["checkout.coupons"].label.contains("意向优惠券"))
        XCTAssertEqual(node(app, "checkout.subtotal").label, subtotal);
        XCTAssertTrue(node(app, "checkout.discount").exists)
        capture(app, "checkout-selections-discount")
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["detail.openSpecifications"].tap()
        XCTAssertEqual(app.staticTexts["detail.spec.quantity"].label, "2")
    }
    @MainActor func testConfirmationContextFailureRetriesWithoutSubmitting() {
        let app = launch("contextFailure"); buy(app, quantity: 1)
        let retry = app.buttons["checkout.retry"];
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label CONTAINS %@", "联系人1"),
                        object: app.buttons["checkout.address"])
                ], timeout: 5) == .completed)
        XCTAssertTrue(app.buttons["checkout.submit"].exists); capture(app, "checkout-context-retry")
    }
    @MainActor func testAddressPickerInterruptionCancelsAndNewPickerAcceptsSelection() {
        let app = launch(); buy(app, quantity: 1)
        XCTAssertTrue(app.buttons["checkout.address"].waitForExistence(timeout: 5))
        app.buttons["checkout.address"].tap()
        XCTAssertTrue(app.buttons["addresses.card.2"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["checkout.address"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addresses.card.2"].exists)
        app.buttons["checkout.address"].tap()
        let address = app.buttons["addresses.card.2"]
        XCTAssertTrue(address.waitForExistence(timeout: 5)); address.tap()
        XCTAssertTrue(app.buttons["checkout.address"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["checkout.address"].label.contains("联系人2"))
    }

    @MainActor func testRepeatedBuyNowPushesOnlyOneConfirmation() {
        let app = launch(); buy(app, quantity: 1, repeated: true)
        XCTAssertTrue(app.staticTexts["checkout.quantity"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.buyNow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["checkout.quantity"].exists)
    }
    @MainActor func testExpiredOrderReadCanReauthenticateAndResumeList() {
        let app = launch("authFailure"); orders(app)
        let reauthenticate = app.buttons["orders.login"]
        XCTAssertTrue(reauthenticate.waitForExistence(timeout: 5)); reauthenticate.tap()
        login(app)
        XCTAssertTrue(app.buttons["orders.item.910001"].waitForExistence(timeout: 5))
        capture(app, "orders-reauthenticated")
    }
    @MainActor func testExpiredCheckoutReadCanReauthenticateWithoutLosingPurchase() {
        let app = launch("authFailure"); buy(app)
        let reauthenticate = app.buttons["checkout.login"]
        XCTAssertTrue(reauthenticate.waitForExistence(timeout: 5)); reauthenticate.tap()
        login(app)
        XCTAssertTrue(app.staticTexts["checkout.quantity"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["checkout.quantity"].label, "数量：2")
        XCTAssertTrue(app.buttons["checkout.address"].label.contains("联系人1"))
        XCTAssertTrue(app.buttons["checkout.submit"].exists)
        capture(app, "checkout-reauthenticated")
    }

    @MainActor func testLargeTextOrderDetailRemainsReadable() {
        let app = launch(large: true); orders(app)
        let first = app.buttons["orders.item.910001"];
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        XCTAssertTrue(app.staticTexts["order.status"].waitForExistence(timeout: 5)); app.swipeUp()
        XCTAssertTrue(node(app, "order.info").exists); capture(app, "order-accessibility")
    }
    @MainActor func testCreateCouponCashierReturnCancelAndBackToProduct() {
        let app = launch(); buy(app, quantity: 1)
        XCTAssertTrue(app.buttons["checkout.address"].waitForExistence(timeout: 5))
        app.buttons["checkout.coupons"].tap()
        let coupon = app.buttons["checkout.coupon.701"]
        XCTAssertTrue(coupon.waitForExistence(timeout: 5)); coupon.tap()
        XCTAssertTrue(node(app, "checkout.discount").exists)
        XCTAssertTrue(app.staticTexts["checkout.address.default"].exists)
        let remark = app.textFields["checkout.remark"]
        app.swipeUp(); XCTAssertTrue(remark.isHittable); remark.tap();
        remark.typeText("Please call")
        capture(app, "confirmation-coupon-discount-remark")
        let submit = app.buttons["checkout.submit"]; XCTAssertTrue(submit.isEnabled);
        submit.doubleTap()
        XCTAssertTrue(app.scrollViews["cashier.page"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["cashier.amount"].label.contains("3,969")
                || app.staticTexts["cashier.amount"].label.contains("3969"))
        capture(app, "cashier-authoritative-amount")
        app.buttons["cashier.back"].tap()
        XCTAssertTrue(app.staticTexts["order.status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["order.status"].label, "待付款")
        app.buttons["order.cancel"].tap()
        let reasonHeader = node(app, "fixedSheet.header")
        let originalHeaderY = reasonHeader.frame.minY
        let reasons = app.scrollViews["order.reason.list"]; reasons.swipeUp()
        XCTAssertEqual(reasonHeader.frame.minY, originalHeaderY, accuracy: 2)
        XCTAssertTrue(app.buttons["order.reason.9"].isHittable)
        reasons.swipeDown()
        let reason = app.buttons["order.reason.1"];
        XCTAssertTrue(reason.waitForExistence(timeout: 5)); reason.tap()
        app.buttons["order.cancel.confirm"].tap()
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label == %@", "已关闭"),
                        object: app.staticTexts["order.status"])
                ], timeout: 5) == .completed)
        XCTAssertFalse(app.buttons["order.cancel"].exists);
        XCTAssertFalse(app.buttons["order.cashier"].exists)
        capture(app, "cancelled-authoritative-closed")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.buyNow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["checkout.submit"].exists)
    }
    @MainActor func testCouponListScrollingDoesNotDismissAndHeaderDragOrBackdropDoes() {
        let app = launch(); buy(app, quantity: 1)
        app.buttons["checkout.coupons"].tap()
        let header = node(app, "fixedSheet.header")
        XCTAssertTrue(header.waitForExistence(timeout: 5)); let original = header.frame.minY
        let shortStart = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        shortStart.press(
            forDuration: 0.1, thenDragTo: shortStart.withOffset(CGVector(dx: 0, dy: 25)))
        XCTAssertTrue(header.exists)
        let list = app.scrollViews["checkout.coupon.list"]; list.swipeUp()
        XCTAssertEqual(header.frame.minY, original, accuracy: 2)
        let fourth = app.buttons["checkout.coupon.704"]; XCTAssertTrue(fourth.isHittable)
        capture(app, "coupon-fixed-height-scroll-fourth")
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)))
        XCTAssertTrue(app.buttons["checkout.coupons"].waitForExistence(timeout: 5))
        XCTAssertFalse(header.exists)
        app.buttons["checkout.coupons"].tap(); XCTAssertTrue(header.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertFalse(header.exists)
    }
    @MainActor func testListDetailCashierReturnsSameDetailThenOriginalListAndGoodsSwipe() {
        let app = launch(); orders(app)
        let first = app.buttons["orders.item.910001"];
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        let carousel = app.scrollViews["order.goods.carousel"];
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        carousel.swipeLeft()
        XCTAssertTrue(carousel.staticTexts["第二件历史商品"].isHittable)
        capture(app, "order-multiple-goods-horizontal")
        app.buttons["order.cashier"].tap()
        XCTAssertTrue(app.scrollViews["cashier.page"].waitForExistence(timeout: 5))
        app.buttons["cashier.back"].tap()
        XCTAssertTrue(app.staticTexts["order.status"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
    }
    @MainActor func testCreateBusinessFailureUsesToastAndPreservesConfirmation() {
        let app = launch("createRejected"); buy(app, quantity: 1)
        let submit = app.buttons["checkout.submit"];
        XCTAssertTrue(submit.waitForExistence(timeout: 5)); submit.tap()
        XCTAssertTrue(app.staticTexts["checkout.toast"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["checkout.toast"].label, "库存不足，请重新选择")
        XCTAssertFalse(app.scrollViews["cashier.page"].exists); XCTAssertTrue(submit.isEnabled)
        capture(app, "create-rejection-server-message")
    }
    @MainActor func testCreateUnknownLocksSubmitWithoutFabricatingCashier() {
        let app = launch("createUnknown"); buy(app, quantity: 1)
        let submit = app.buttons["checkout.submit"];
        XCTAssertTrue(submit.waitForExistence(timeout: 5)); submit.tap()
        XCTAssertTrue(app.staticTexts["checkout.toast"].waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled); XCTAssertFalse(app.scrollViews["cashier.page"].exists)
        capture(app, "create-unknown-no-replay")
    }

    @MainActor func testCancelReasonAuthenticationCanLoginAndResumeDetail() {
        let app = launch("reasonAuthFailure"); orders(app)
        let first = app.buttons["orders.item.910001"];
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        let cancel = app.buttons["order.cancel"];
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5)); login(app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["order.reason.1"].waitForExistence(timeout: 5))
        capture(app, "cancel-reason-authentication-resumed")
    }

    @MainActor func testSparseCheckoutCouponsAreSelectableAndNoSelectionMeansNoDiscount() {
        let app = launch("checkoutSparseCoupon"); buy(app, quantity: 1)
        XCTAssertTrue(app.buttons["checkout.coupons"].waitForExistence(timeout: 5))
        XCTAssertFalse(node(app, "checkout.discount").exists)
        let originalTotal = node(app, "checkout.total").label
        app.buttons["checkout.coupons"].tap()
        let first = app.buttons["checkout.coupon.701"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["不使用优惠券"].exists)
        XCTAssertFalse(app.buttons["checkout.coupon.none"].exists)
        XCTAssertFalse(app.buttons["checkout.submit"].exists)
        XCTAssertFalse(app.buttons["checkout.address"].exists)
        for id in [701, 702, 703] {
            XCTAssertTrue(app.buttons["checkout.coupon.\(id)"].isEnabled)
        }
        let list = app.scrollViews["checkout.coupon.list"]; list.swipeUp()
        let fourth = app.buttons["checkout.coupon.704"]
        XCTAssertTrue(fourth.isHittable); XCTAssertFalse(fourth.isEnabled)
        XCTAssertEqual(fourth.label, "未满9999元")
        capture(app, "coupon-real-threshold-reason")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertFalse(node(app, "checkout.discount").exists)
        XCTAssertEqual(node(app, "checkout.total").label, originalTotal)
        app.buttons["checkout.coupons"].tap(); first.tap()
        XCTAssertTrue(node(app, "checkout.discount").exists)
        XCTAssertTrue(
            node(app, "checkout.total").label.contains("3,969")
                || node(app, "checkout.total").label.contains("3969"))
        app.buttons["checkout.coupons"].tap()
        XCTAssertEqual(first.label, "已选择"); first.tap()
        XCTAssertFalse(node(app, "checkout.discount").exists)
        XCTAssertEqual(node(app, "checkout.total").label, originalTotal)
        capture(app, "coupon-deselected-no-deduction")
    }

}
