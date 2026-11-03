import XCTest

@MainActor private enum CouponSystemUI {
    static func dismissPasswordPrompt(in app: XCUIApplication) {
        // Password AutoFill can arrive after login, even after the destination is visible.
        // Refuse saving the synthetic credential; do not dismiss unrelated alerts.
        for surface in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            guard isPasswordPrompt(surface) else { continue }
            let later = surface.buttons["以后"]
            if later.exists && later.isHittable { later.tap(); return }
            let notNow = surface.buttons["Not Now"]
            if notNow.exists && notNow.isHittable { notNow.tap(); return }
        }
    }
    static func isPasswordPrompt(_ surface: XCUIElement) -> Bool {
        surface.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "保存密码")).firstMatch
            .exists
            || surface.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Save Password")
            ).firstMatch.exists
    }
}

final class CouponFlowTests: XCTestCase {
    @MainActor private func app(_ scenario: String = "success", large: Bool = false)
        -> XCUIApplication
    {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Password AutoFill save prompt") { alert in
            guard CouponSystemUI.isPasswordPrompt(alert) else { return false }
            for title in ["以后", "Not Now"] {
                let later = alert.buttons[title]
                if later.exists { later.tap(); return true }
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-banner-manual", "--ui-product-detail-fixture",
            "valid", "--ui-cart-store", UUID().uuidString, "--ui-account-fixture", "success",
            "--ui-coupons", scenario,
        ]
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10));
        app.tabBars.buttons["我的"].tap()
        let entry = app.buttons["me.coupons"]
        for _ in 0..<6 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func login(_ app: XCUIApplication) {
        let choose = app.buttons["login.choosePassword"]
        for _ in 0..<5 { if choose.isHittable { break }; app.swipeUp() }
        choose.tap()
        let phone = app.textFields["login.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5)); phone.tap();
        phone.typeText("13800000000")
        app.secureTextFields["login.password"].tap();
        app.secureTextFields["login.password"].typeText("test-only")
        let done = app.toolbars.buttons["完成"]; if done.exists { done.tap() }
        let submit = app.buttons["login.submit"]
        for _ in 0..<5 { if submit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(submit.isEnabled); submit.tap()
        XCTAssertTrue(app.scrollViews["coupons.page"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["我的优惠券"].exists)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name;
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func pull(_ app: XCUIApplication) {
        let scroll = app.scrollViews["coupons.page"]
        let visible = scroll.frame.intersection(app.frame)
        let top = max(visible.minY, app.navigationBars.firstMatch.frame.maxY)
        let bottom = visible.maxY - 44
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: visible.minX + 24, dy: top + 24))
        let end = origin.withOffset(CGVector(dx: visible.minX + 24, dy: bottom - 16))
        let geometry = XCTAttachment(
            string:
                "viewport=\(visible), nav=\(app.navigationBars.firstMatch.frame), start=(\(visible.minX + 24),\(top + 24)), endY=\(bottom - 16)"
        )
        geometry.name = "coupons-real-pull-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        capture(app, "coupons-before-real-pull")
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    @MainActor func testGuestCancelThenLoginResumesCouponsRulesAndGoUseDetailBack() {
        let app = app()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["me.coupons"].waitForExistence(timeout: 5));
        app.buttons["me.coupons"].tap()
        login(app)
        let rule = app.buttons["coupons.rules.701"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5)); rule.tap()
        XCTAssertTrue(app.staticTexts["coupons.description.701"].exists)
        XCTAssertFalse(app.staticTexts["coupons.description.702"].exists)
        capture(app, "coupons-rules-expanded")
        rule.tap(); XCTAssertFalse(app.staticTexts["coupons.description.701"].exists)
        app.buttons["coupons.use.701"].tap()
        XCTAssertTrue(app.buttons["couponProducts.item.830001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["couponProducts.minimum"].label.contains("299"));
        capture(app, "coupon-price-products")
        app.buttons["couponProducts.item.830001"].tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5));
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["couponProducts.item.830001"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap();
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
    }
    @MainActor func testEmptyReloadAndRealPullRefresh() {
        let app = app("empty"); login(app)
        XCTAssertTrue(app.staticTexts["coupons.empty"].waitForExistence(timeout: 5));
        capture(app, "coupons-empty")
        app.buttons["coupons.reload"].tap(); pull(app)
        XCTAssertTrue(app.staticTexts["coupons.empty"].waitForExistence(timeout: 5))
    }
    @MainActor func testInitialFailureRetriesAndUsedCouponCannotNavigate() {
        let app = app("initialFailure"); login(app)
        let retry = app.buttons["coupons.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); capture(app, "coupons-initial-failure");
        retry.tap()
        XCTAssertTrue(app.buttons["coupons.use.701"].waitForExistence(timeout: 5))
        let used = app.buttons["coupons.use.703"]
        for _ in 0..<5 { if used.exists { break }; app.swipeUp() }
        XCTAssertTrue(used.exists); XCTAssertFalse(used.isEnabled)
    }
    @MainActor func testRealPullFailureRetainsCardsAndRetryRecovers() {
        let app = app("refreshFailure"); login(app)
        XCTAssertTrue(app.buttons["coupons.use.701"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coupons.retry"].exists); pull(app)
        capture(app, "coupons-after-real-pull")
        XCTAssertTrue(app.buttons["coupons.retry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["coupons.use.701"].exists);
        capture(app, "coupons-refresh-failure")
        app.buttons["coupons.retry"].tap();
        XCTAssertTrue(app.buttons["coupons.retry"].waitForNonExistence(timeout: 5))
    }
    @MainActor func testAppendFailureRetriesSamePageAndShowsEnd() {
        let app = app("appendFailure"); login(app)
        let more = app.buttons["coupons.more"]
        for _ in 0..<15 {
            CouponSystemUI.dismissPasswordPrompt(in: app)
            if more.isHittable { break }; app.swipeUp()
        }
        if !more.isHittable {
            capture(app, "coupons-unreachable-append")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "coupons-unreachable-append-hierarchy";
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(more.isHittable)
        XCTAssertTrue(app.staticTexts["请求超时，请重试"].waitForExistence(timeout: 5));
        capture(app, "coupons-append-failure")
        more.tap()
        let last = app.buttons["coupons.use.712"]
        for _ in 0..<5 { if last.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(last.isHittable); XCTAssertTrue(app.staticTexts["coupons.end"].exists)
    }
    @MainActor func testAppendAuthenticationFailureCanReloginAndResume() {
        let app = app("appendAuthFailure"); login(app)
        let more = app.buttons["coupons.more"]
        for _ in 0..<15 {
            CouponSystemUI.dismissPasswordPrompt(in: app)
            if more.isHittable { break }; app.swipeUp()
        }
        XCTAssertTrue(more.isHittable)
        XCTAssertTrue(app.staticTexts["请重新登录后查看优惠券"].waitForExistence(timeout: 5))
        XCTAssertEqual(more.label, "重新登录"); more.tap()
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5)); login(app)
        capture(app, "coupons-relogin-return-position")
        let position = XCTAttachment(string: app.debugDescription)
        position.name = "coupons-relogin-return-hierarchy"; position.lifetime = .keepAlways;
        add(position)
        let first = app.buttons["coupons.use.701"]
        for _ in 0..<12 {
            if first.exists && first.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(first.isHittable)
        XCTAssertFalse(app.staticTexts["请重新登录后查看优惠券"].exists)
        capture(app, "coupons-relogin-resumed")
    }
    @MainActor func testAccessibilityLayoutRulesRemainReachable() {
        let app = app(large: true); login(app)
        let rules = app.buttons["coupons.rules.701"]
        for _ in 0..<6 { if rules.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(rules.isHittable); rules.tap()
        XCTAssertTrue(app.staticTexts["coupons.description.701"].exists)
        let use = app.buttons["coupons.use.701"]
        XCTAssertTrue(use.isHittable); capture(app, "coupons-accessibility"); use.tap()
        XCTAssertTrue(app.buttons["couponProducts.item.830001"].waitForExistence(timeout: 5))
        capture(app, "coupon-products-accessibility")
    }
}

final class CouponReceiveFlowTests: XCTestCase {
    private var selectedCouponID: Int64 = 860001
    @MainActor private func app(
        _ scenario: String = "receiveSuccess", large: Bool = false,
        home: String = "valid", automatic: Bool = false
    )
        -> XCUIApplication
    {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Password AutoFill save prompt") { alert in
            guard CouponSystemUI.isPasswordPrompt(alert) else { return false }
            for title in ["以后", "Not Now"] {
                let later = alert.buttons[title]
                if later.exists { later.tap(); return true }
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", home, "--ui-banner-manual", "--ui-product-detail-fixture",
            "valid", "--ui-cart-store", UUID().uuidString, "--ui-account-fixture", "success",
            "--ui-coupons", scenario,
        ]
        if automatic { app.launchArguments.removeAll { $0 == "--ui-banner-manual" } }
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch(); XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10));
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, count: Int = 8)
    {
        for _ in 0..<count {
            CouponSystemUI.dismissPasswordPrompt(in: app)
            let exists = element.exists
            if exists && element.isHittable { return }
            let screen = app.frame
            let navBottom =
                app.navigationBars.firstMatch.exists
                ? app.navigationBars.firstMatch.frame.maxY : screen.minY + 64
            var bottom = screen.maxY - 44
            // Drag inside visible content, never on the keyboard or floating input accessory.
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists {
                bottom = min(bottom, keyboard.frame.minY - 12)
                let done = app.toolbars.buttons["完成"]
                if done.exists { bottom = min(bottom, done.frame.minY - 12) }
            }
            var top = navBottom + 16
            let list = app.scrollViews["couponClaim.list"]
            if exists && element.identifier.hasPrefix("couponClaim."), list.exists {
                top = max(top, list.frame.minY + 8)
                bottom = min(bottom, list.frame.maxY - 8)
            }
            XCTAssertGreaterThan(bottom - top, 80)
            let above = exists && element.frame.maxY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(
                CGVector(
                    dx: screen.minX + 20, dy: top + (bottom - top) * (above ? 0.2 : 0.8)))
            let end = origin.withOffset(
                CGVector(
                    dx: screen.minX + 20, dy: top + (bottom - top) * (above ? 0.8 : 0.2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        capture(app, "claim-unreachable-element")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "claim-unreachable-hierarchy"; hierarchy.lifetime = .keepAlways;
        add(hierarchy)
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func dismissOverlay(_ app: XCUIApplication) {
        let panel = app.otherElements["couponClaim.panel"]
        XCTAssertTrue(panel.exists)
        XCTAssertGreaterThan(panel.frame.minY, 80)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: panel.frame.minY / 2)).tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
    }
    @MainActor private func homeOffer(_ app: XCUIApplication, second: Bool = false) {
        selectedCouponID = second ? 860002 : 860001
        let button = app.buttons["home.coupon.860001.claim"]; reveal(button, in: app)
        if second {
            app.staticTexts["home.coupon.860001.title"].swipeLeft()
            let selected = app.buttons["home.coupon.860002.claim"]
            XCTAssertTrue(selected.waitForExistence(timeout: 5)); selected.tap()
        } else {
            button.tap()
        }
        XCTAssertTrue(
            app.staticTexts["couponClaim.title.\(selectedCouponID)"].waitForExistence(timeout: 5))
    }
    @MainActor private func login(_ app: XCUIApplication) {
        let login = app.buttons["couponClaim.confirm.\(selectedCouponID)"]; reveal(login, in: app);
        login.tap()
        let password = app.buttons["login.choosePassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5)); reveal(password, in: app);
        password.tap()
        let phone = app.textFields["login.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5)); reveal(phone, in: app); phone.tap();
        phone.typeText("13800000000")
        let secret = app.secureTextFields["login.password"]
        reveal(secret, in: app); tapVisiblePassword(app)
        secret.typeText("test-only")
        let done = app.toolbars.buttons["完成"]; if done.exists { done.tap() }
        let submit = app.buttons["login.submit"]; reveal(submit, in: app); submit.tap()
        XCTAssertTrue(
            app.buttons["couponClaim.confirm.\(selectedCouponID)"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            (app.buttons["couponClaim.confirm.\(selectedCouponID)"].value as? String == "已领取"))
    }
    @MainActor private func tapVisiblePassword(_ app: XCUIApplication) {
        func descendants(_ node: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            [node] + node.children.flatMap { descendants($0) }
        }
        for _ in 0..<3 {
            guard let root = try? app.snapshot() else { return XCTFail("Cannot observe login") }
            let nodes = descendants(root)
            guard let field = nodes.first(where: { $0.identifier == "login.password" })
            else { return XCTFail("Cannot observe password input") }
            let top =
                (nodes.first(where: { $0.elementType == .navigationBar })?.frame.maxY
                    ?? root.frame.minY + 64) + 12
            var bottom = root.frame.maxY - 44
            if let keyboard = nodes.first(where: { $0.elementType == .keyboard }) {
                bottom = min(bottom, keyboard.frame.minY - 12)
            }
            if let done = nodes.first(where: { $0.elementType == .button && $0.label == "完成" }) {
                bottom = min(bottom, done.frame.minY - 12)
            }
            let visible = field.frame.intersection(
                CGRect(
                    x: root.frame.minX, y: top, width: root.frame.width,
                    height: max(0, bottom - top)))
            if visible.height >= min(24, field.frame.height) && visible.width > 0 {
                let geometry = XCTAttachment(
                    string: "Password frame: \(field.frame); visible: \(visible)")
                geometry.name = "claim-password-input-geometry"; geometry.lifetime = .keepAlways
                add(geometry)
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
                return
            }
            XCTAssertGreaterThan(bottom - top, 80)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: 20, dy: top + (bottom - top) * 0.8))
                .press(
                    forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: 20, dy: top + (bottom - top) * 0.2)))
        }
        XCTFail("Password input remained obscured")
    }
    @MainActor private func hasStatus(_ app: XCUIApplication, _ value: String, id: Int64? = nil)
        -> Bool
    {
        let button = app.buttons["couponClaim.confirm.\(id ?? selectedCouponID)"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: button)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
    @MainActor private func expectToast(_ app: XCUIApplication, _ message: String) {
        let toast = app.staticTexts["couponClaim.toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, message)
    }
    @MainActor private func openOwnedAfterDismissal(_ app: XCUIApplication) {
        dismissOverlay(app); app.tabBars.buttons["我的"].tap()
        let entry = app.buttons["me.coupons"]; XCTAssertTrue(entry.waitForExistence(timeout: 5));
        entry.tap()
    }
    @MainActor private func dragHeaderDown(_ app: XCUIApplication) {
        let header = app.otherElements["couponClaim.dragHandle"]
        XCTAssertTrue(header.exists)
        let frame = header.frame; let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY + 180)))
        XCTAssertTrue(app.otherElements["couponClaim.panel"].waitForNonExistence(timeout: 5))
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name;
        a.lifetime = .keepAlways; add(a)
    }
    @MainActor func testHeaderDownClosesWhileListScrollAndOtherDirectionsDoNot() {
        let app = app(home: "coupon-many"); homeOffer(app)
        let list = app.scrollViews["couponClaim.list"]
        let last = app.buttons["couponClaim.confirm.860007"]; reveal(last, in: app)
        XCTAssertTrue(last.isHittable)
        list.swipeDown()
        XCTAssertTrue(app.otherElements["couponClaim.panel"].exists)
        let first = app.buttons["couponClaim.confirm.860001"]; reveal(first, in: app)
        XCTAssertTrue(first.isHittable)
        let frame = app.otherElements["couponClaim.dragHandle"].frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        start.press(
            forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: frame.midX + 100, dy: frame.midY)))
        XCTAssertTrue(app.otherElements["couponClaim.panel"].exists)
        start.press(
            forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY - 90)))
        XCTAssertTrue(app.otherElements["couponClaim.panel"].exists)
        capture(app, "coupon-list-scroll-does-not-dismiss")
        dragHeaderDown(app); XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
    }
    @MainActor func testReceivedToastExpiresAndRepeatsWithoutMovingButton() {
        let app = app(); homeOffer(app); login(app)
        let button = app.buttons["couponClaim.confirm.860001"]; let before = button.frame
        button.tap(); expectToast(app, "已领取")
        XCTAssertEqual(button.frame.minY, before.minY, accuracy: 1)
        XCTAssertEqual(button.frame.minX, before.minX, accuracy: 1)
        XCTAssertEqual(button.frame.width, before.width, accuracy: 1)
        capture(app, "claim-received-toast")
        XCTAssertTrue(app.staticTexts["couponClaim.toast"].waitForNonExistence(timeout: 5))
        button.tap(); expectToast(app, "已领取")
        XCTAssertEqual(button.label, "立即领取"); XCTAssertEqual(button.value as? String, "已领取")
        XCTAssertFalse(app.buttons["couponClaim.viewOwned.860001"].exists)
    }
    @MainActor func testServerMessageToastKeepsButtonStableAndRejectionIsNotReceipt() {
        let app = app("receiveMessage"); homeOffer(app); login(app)
        let button = app.buttons["couponClaim.confirm.860001"]; let before = button.frame
        button.tap(); expectToast(app, "已领取过该优惠券")
        XCTAssertEqual(button.frame.minY, before.minY, accuracy: 1)
        XCTAssertNotEqual(button.value as? String, "已领取")
        capture(app, "claim-server-message-rejection")
        button.tap(); expectToast(app, "优惠券领取成功")
        XCTAssertEqual(button.frame.minY, before.minY, accuracy: 1)
        XCTAssertTrue(hasStatus(app, "已领取"))
        XCTAssertEqual(button.label, "立即领取")
        XCTAssertFalse(app.buttons["couponClaim.viewOwned.860001"].exists)
    }
    @MainActor func testClaimFailureUsesToastWithoutMovingButton() {
        let app = app("receiveReject"); homeOffer(app); login(app)
        let button = app.buttons["couponClaim.confirm.860001"]
        let before = button.frame
        button.tap()
        XCTAssertTrue(app.staticTexts["couponClaim.toast"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["couponClaim.toast"].label, "领取失败")
        XCTAssertEqual(button.frame.minY, before.minY, accuracy: 1)
        XCTAssertEqual(button.frame.minX, before.minX, accuracy: 1)
        XCTAssertFalse(app.staticTexts["couponClaim.failure.860001"].exists)
        XCTAssertFalse(app.buttons["couponClaim.viewOwned.860001"].exists)
        capture(app, "claim-toast-stable-button")
    }
    @MainActor func testHomeAllReturnedCouponsUsePartialOverlayAndOutsideDismissal() {
        let app = app(); homeOffer(app)
        capture(app, "home-coupon-overlay-before-assertions")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "home-coupon-overlay-hierarchy"; tree.lifetime = .keepAlways; add(tree)
        XCTAssertTrue(app.staticTexts["couponClaim.title.860003"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["couponClaim.close"].exists)
        let sheet = app.otherElements["couponClaim.panel"]
        XCTAssertGreaterThan(sheet.frame.minY, app.frame.height * 0.2)
        for id in [860001, 860002, 860003] {
            let claim = app.buttons["couponClaim.confirm.\(id)"]
            XCTAssertEqual(claim.label, "立即领取")
            XCTAssertTrue(claim.isHittable)
            XCTAssertTrue(sheet.frame.contains(claim.frame))
        }
        dismissOverlay(app)
        XCTAssertTrue(app.staticTexts["couponClaim.title.860001"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
    }
    @MainActor func testMoreThanThreeCouponsScrollAndKeepIndependentReceipts() {
        let app = app(home: "coupon-many"); homeOffer(app); login(app)
        app.buttons["couponClaim.confirm.860001"].tap()
        XCTAssertTrue(hasStatus(app, "已领取", id: 860001))
        let last = app.buttons["couponClaim.confirm.860007"]; reveal(last, in: app); last.tap()
        XCTAssertTrue(hasStatus(app, "已领取", id: 860007))
        let first = app.buttons["couponClaim.confirm.860001"]; reveal(first, in: app)
        XCTAssertTrue(first.isHittable); XCTAssertEqual(first.value as? String, "已领取")
        XCTAssertEqual(first.label, "立即领取")
        app.buttons["couponClaim.rules.860001"].tap()
        XCTAssertTrue(app.staticTexts["couponClaim.description.860001"].exists)
        XCTAssertEqual(app.buttons["couponClaim.rules.860002"].value as? String, "已收起")
        capture(app, "seven-coupons-retain-independent-receipts")
    }
    @MainActor func testOutsideDismissalWhileReceivingReturnsHomeWithoutAutomaticClaim() {
        let app = app("receivePending"); homeOffer(app); login(app)
        let button = app.buttons["couponClaim.confirm.860001"]; let before = button.frame
        button.tap(); XCTAssertTrue(hasStatus(app, "正在领取")); XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.frame.minY, before.minY, accuracy: 1)
        XCTAssertEqual(button.label, "立即领取")
        dismissOverlay(app); XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
        homeOffer(app)
        XCTAssertEqual(app.buttons["couponClaim.confirm.860001"].value as? String, "")
        XCTAssertFalse(app.staticTexts["couponClaim.toast"].exists)
        XCTAssertFalse(app.buttons["couponClaim.stop.860001"].exists)
    }
    @MainActor func testHomeImagesRemainColoredBehindCouponOverlayWithoutReload() {
        let app = app(home: "coupon-many")
        let image = app.buttons["home.image.success"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        let loading = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                app.descendants(matching: .any).matching(identifier: "home.image.loading").count
                    == 0
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loading], timeout: 5), .completed)
        let originalFrame = image.frame
        let metrics = app.staticTexts["home.image.metrics"].label
        homeOffer(app)
        let panel = app.otherElements["couponClaim.panel"]
        let visible = originalFrame.intersection(
            CGRect(
                x: 0, y: 0, width: app.frame.width, height: panel.frame.minY - 8))
        XCTAssertGreaterThan(visible.height, 8)
        capture(app, "home-colored-images-behind-coupon-overlay")
        let screen = app.screenshot().image
        guard let pixels = screen.cgImage else { return XCTFail("Missing screenshot pixels") }
        let scale = CGFloat(pixels.width) / app.frame.width
        guard
            let sample = pixels.cropping(
                to: CGRect(
                    x: floor(visible.midX * scale), y: floor(visible.midY * scale), width: 1,
                    height: 1))
        else { return XCTFail("Missing visible banner sample") }
        var rgba = [UInt8](repeating: 0, count: 4)
        let color = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: color, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return XCTFail("Cannot read banner color") }
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        // The controlled image is blue; the old disabled-image placeholder is gray.
        XCTAssertGreaterThan(Int(rgba[2]) - Int(rgba[0]), 30)
        dismissOverlay(app)
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.image.metrics"].label, metrics)
    }
    @MainActor func testCouponOverlayPausesBannerAndDismissalResumesAutoplay() {
        let app = app(home: "coupon-many", automatic: true)
        let query = NSPredicate(format: "identifier BEGINSWITH %@", "home.banner.current.")
        let current = app.buttons.matching(query).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        current.swipeLeft()
        let selectedID = app.buttons.matching(query).firstMatch.identifier
        homeOffer(app)
        let interval = expectation(
            description: "Keep coupon modal open longer than one banner period")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.6) { interval.fulfill() }
        wait(for: [interval], timeout: 6.6)
        dismissOverlay(app)
        XCTAssertTrue(app.buttons[selectedID].exists)
        XCTAssertTrue(app.buttons[selectedID].waitForNonExistence(timeout: 9))
        XCTAssertTrue(app.buttons.matching(query).firstMatch.exists)
        capture(app, "coupon-dismissal-banner-autoplay-resumed")
    }
    @MainActor func testHomeSelectedCouponLoginCancelThenExplicitClaimReadsOwnedCoupon() {
        let app = app(); homeOffer(app, second: true)
        XCTAssertTrue(
            app.staticTexts["couponClaim.title.\(selectedCouponID)"].label.contains("小米家电"))
        app.buttons["couponClaim.confirm.\(selectedCouponID)"].tap();
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["couponClaim.confirm.\(selectedCouponID)"].waitForExistence(timeout: 5));
        XCTAssertFalse(
            (app.buttons["couponClaim.confirm.\(selectedCouponID)"].value as? String == "已领取"))
        login(app); capture(app, "home-claim-confirm-after-login")
        app.buttons["couponClaim.confirm.\(selectedCouponID)"].tap()
        XCTAssertTrue(
            hasStatus(app, "已领取", id: selectedCouponID)
        );
        capture(app, "home-claim-received")
        openOwnedAfterDismissal(app)
        XCTAssertTrue(app.buttons["coupons.use.860002"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coupons.use.860001"].exists)
    }
    @MainActor func testDetailSelectedCouponClosesOverlayAndReturnsToOriginalDetail() {
        let app = app(); let card = app.buttons["home.flashSale.830001.card"];
        reveal(card, in: app); card.tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        let coupon = app.buttons["detail.coupon.860001"]; reveal(coupon, in: app); coupon.tap()
        let receive = app.buttons["detail.coupon.receive.860002"]; reveal(receive, in: app);
        receive.tap(); selectedCouponID = 860002
        XCTAssertTrue(
            app.staticTexts["couponClaim.title.\(selectedCouponID)"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["couponClaim.title.\(selectedCouponID)"].label.contains("小米家电"));
        login(app)
        app.buttons["couponClaim.confirm.\(selectedCouponID)"].tap();
        XCTAssertTrue(
            hasStatus(app, "已领取", id: selectedCouponID)
        )
        capture(app, "detail-claim-received"); dismissOverlay(app)
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["detail.loaded"].label.contains("830001"))
        XCTAssertFalse(app.buttons["detail.coupon.receive.860002"].exists)
        app.buttons["detail.back"].tap();
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
    }
    @MainActor func testBusinessRejectionOnlyRetriesAfterExplicitTapAndKeepsHomeSelection() {
        let app = app("receiveReject"); homeOffer(app, second: true); login(app)
        let button = app.buttons["couponClaim.confirm.\(selectedCouponID)"];
        let before = button.frame
        button.tap(); expectToast(app, "领取失败")
        XCTAssertEqual(button.frame.minY, before.minY, accuracy: 1)
        XCTAssertFalse(app.staticTexts["couponClaim.failure.\(selectedCouponID)"].exists)
        capture(app, "claim-business-rejection-toast")
        button.tap(); XCTAssertTrue(hasStatus(app, "已领取"))
        XCTAssertEqual(button.frame.minY, before.minY, accuracy: 1)
        dismissOverlay(app)
        XCTAssertTrue(app.buttons["home.coupon.860002.claim"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
    }
    @MainActor func testUnconfirmedWriteOffersOwnedReadWithoutRetryOrFakeSuccess() {
        let app = app("receiveUnknown"); homeOffer(app); login(app)
        let button = app.buttons["couponClaim.confirm.\(selectedCouponID)"];
        let before = button.frame
        button.tap(); expectToast(app, "领取失败，结果未确认，请稍后核对")
        XCTAssertTrue(hasStatus(app, "结果待核对"))
        XCTAssertEqual(button.frame.minY, before.minY, accuracy: 1)
        XCTAssertFalse(app.buttons["couponClaim.viewOwned.\(selectedCouponID)"].exists)
        button.tap(); expectToast(app, "领取失败，结果未确认，请稍后核对")
        capture(app, "claim-unconfirmed-toast")
        openOwnedAfterDismissal(app)
        XCTAssertTrue(app.staticTexts["coupons.empty"].waitForExistence(timeout: 5))
    }
    @MainActor func testHeaderDismissalWhileReceivingNeverAutomaticallyReplays() {
        let app = app("receivePending"); homeOffer(app); login(app)
        app.buttons["couponClaim.confirm.\(selectedCouponID)"].tap()
        XCTAssertTrue(hasStatus(app, "正在领取"))
        XCTAssertFalse(app.buttons["couponClaim.stop.\(selectedCouponID)"].exists)
        dragHeaderDown(app)
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
        homeOffer(app)
        XCTAssertEqual(app.buttons["couponClaim.confirm.\(selectedCouponID)"].value as? String, "")
        XCTAssertFalse(app.staticTexts["couponClaim.toast"].exists)
    }
    @MainActor func testSameAccountReauthenticationStillRequiresNewExplicitClaim() {
        let app = app("receiveAuthFailure"); homeOffer(app); login(app)
        app.buttons["couponClaim.confirm.\(selectedCouponID)"].tap()
        expectToast(app, "领取失败，请重新登录")
        login(app)
        XCTAssertNotEqual(
            app.buttons["couponClaim.confirm.\(selectedCouponID)"].value as? String, "已领取")
        app.buttons["couponClaim.confirm.\(selectedCouponID)"].tap()
        XCTAssertTrue(hasStatus(app, "已领取")); capture(app, "claim-same-account-relogin")
    }
    @MainActor func testLargeTextUnconfirmedControlsRemainReachable() {
        let app = app("receiveUnknown", large: true); homeOffer(app); login(app)
        let confirm = app.buttons["couponClaim.confirm.\(selectedCouponID)"]
        reveal(confirm, in: app); let before = confirm.frame; confirm.tap()
        expectToast(app, "领取失败，结果未确认，请稍后核对")
        XCTAssertEqual(confirm.frame.minY, before.minY, accuracy: 1)
        capture(app, "claim-accessibility-toast")
        openOwnedAfterDismissal(app)
        XCTAssertTrue(app.staticTexts["coupons.empty"].waitForExistence(timeout: 5))
    }
    @MainActor private func tapCaptchaConfirm(_ app: XCUIApplication) {
        let button = app.buttons["login.captcha.confirm"]
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.isHittable)
        func descendants(_ node: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            [node] + node.children.flatMap { descendants($0) }
        }
        guard let root = try? app.snapshot(),
            let confirm = descendants(root).first(where: {
                $0.identifier == "login.captcha.confirm"
            })
        else {
            XCTFail("Cannot observe CAPTCHA submit in current full snapshot")
            return
        }
        let nodes = descendants(root)
        let frame = confirm.frame
        XCTAssertTrue(root.frame.contains(frame))
        if let keyboard = nodes.first(where: { $0.elementType == .keyboard }) {
            XCTAssertLessThan(frame.maxY, keyboard.frame.minY)
        }
        let geometry = XCTAttachment(
            string: "CAPTCHA full snapshot confirm frame: \(frame)")
        geometry.name = "captcha-confirm-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        // Keep button and keyboard geometry in the same full observation.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }
    @MainActor func testCodeLoginNestedCaptchaInsideClaimSheetRequiresExplicitConfirmation() {
        let app = app(); homeOffer(app);
        app.buttons["couponClaim.confirm.\(selectedCouponID)"].tap()
        XCTAssertTrue(app.buttons["login.chooseCode"].waitForExistence(timeout: 5));
        app.buttons["login.chooseCode"].tap()
        let phone = app.textFields["login.phone"];
        XCTAssertTrue(phone.waitForExistence(timeout: 5)); phone.tap();
        phone.typeText("13800000000")
        if app.toolbars.buttons["完成"].exists { app.toolbars.buttons["完成"].tap() }
        app.buttons["login.requestCode"].tap()
        let answer = app.textFields["login.captcha.answer"];
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        capture(app, "claim-nested-captcha")
        answer.tap(); answer.typeText("1234")
        XCTAssertFalse(app.navigationBars.buttons["取消"].exists)
        XCTAssertFalse(app.toolbars.buttons["完成"].exists)
        tapCaptchaConfirm(app)
        XCTAssertTrue(app.staticTexts["login.notice"].waitForExistence(timeout: 5))
        let code = app.textFields["login.code"]; code.tap(); code.typeText("2468")
        if app.toolbars.buttons["完成"].exists { app.toolbars.buttons["完成"].tap() }
        app.buttons["login.submit"].tap()
        XCTAssertTrue(
            app.buttons["couponClaim.confirm.\(selectedCouponID)"].waitForExistence(timeout: 5));
        XCTAssertFalse(
            (app.buttons["couponClaim.confirm.\(selectedCouponID)"].value as? String == "已领取"))
        app.buttons["couponClaim.confirm.\(selectedCouponID)"].tap();
        XCTAssertTrue(
            hasStatus(app, "已领取", id: selectedCouponID)
        )
        capture(app, "claim-code-login-received")
    }

}
