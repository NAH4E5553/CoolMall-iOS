import XCTest

final class AccountLoginFlowTests: XCTestCase {
    @MainActor private func app(
        _ scenario: String = "success", large: Bool = false, seed: Bool = false,
        systemNotification: Bool = false, keychain: String? = nil
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-banner-manual",
            "--ui-product-detail-fixture", "valid",
            "--ui-cart-store", UUID().uuidString, "--ui-account-fixture", scenario,
        ]
        if let keychain { app.launchArguments += ["--ui-account-keychain", keychain] }
        if seed { app.launchArguments.append("--ui-cart-seed") }
        if systemNotification { app.launchArguments.append("--ui-account-system-notification") }
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func phone(_ app: XCUIApplication) {
        let field = app.textFields["login.phone"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap();
        field.typeText("13800000000")
    }
    @MainActor private func hideKeyboard(_ app: XCUIApplication) {
        let done = app.toolbars.buttons["完成"]
        if done.exists { done.tap() }
    }
    @MainActor func testPasswordLoginReadOnlyProfileLogoutRestoresGuestCart() {
        let app = app(seed: true)
        capture(app, "me-guest")
        app.buttons["me.account"].tap()
        capture(app, "login-choice")
        app.buttons["login.choosePassword"].tap()
        XCTAssertFalse(app.buttons["login.submit"].isEnabled)
        phone(app)
        app.secureTextFields["login.password"].tap()
        app.secureTextFields["login.password"].typeText("test-only")
        hideKeyboard(app)
        capture(app, "password-filled")
        XCTAssertTrue(app.buttons["login.submit"].isEnabled); app.buttons["login.submit"].tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.account"].label.contains("测试用户"))
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.empty"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap(); app.buttons["me.account"].tap()
        XCTAssertTrue(app.staticTexts["账号、920001"].waitForExistence(timeout: 5))
        capture(app, "profile-read-only")
        let logout = app.buttons["profile.logout"]
        for _ in 0..<3 { if logout.isHittable { break }; app.swipeUp() }
        logout.tap()
        app.sheets["退出当前账号？"].buttons.matching(identifier: "profile.confirmLogout").firstMatch.tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.account"].label.contains("未登录"))
        app.tabBars.buttons["购物车"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cart.quantity.830001.1"].label, "1")
    }
    @MainActor func testRealAppKeychainCodeLoginRestoresAfterRestartAndLogoutDeletes() {
        let app = app(keychain: UUID().uuidString)
        app.buttons["me.account"].tap(); app.buttons["login.chooseCode"].tap()
        phone(app)
        let code = app.textFields["login.code"]; code.tap(); code.typeText("2468")
        hideKeyboard(app); app.buttons["login.submit"].tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.account"].label.contains("Keychain测试用户"))
        app.terminate(); app.launch()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.account"].label.contains("Keychain测试用户"))
        capture(app, "actual-app-keychain-restored")
        app.buttons["me.account"].tap()
        let logout = app.buttons["profile.logout"]
        for _ in 0..<3 { if logout.isHittable { break }; app.swipeUp() }
        logout.tap()
        app.sheets["退出当前账号？"].buttons.matching(identifier: "profile.confirmLogout").firstMatch.tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.account"].label.contains("未登录"))
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
    @MainActor func testCodeChallengeDeliveryAndLogin() {
        let app = app()
        app.buttons["me.account"].tap(); app.buttons["login.chooseCode"].tap()
        capture(app, "code-empty")
        phone(app); hideKeyboard(app)
        app.buttons["login.requestCode"].tap()
        let answer = app.textFields["login.captcha.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        capture(app, "captcha-sheet")
        XCTAssertFalse(app.navigationBars.buttons["取消"].exists)
        answer.tap(); answer.typeText("0000")
        XCTAssertFalse(app.toolbars.buttons["完成"].exists)
        tapCaptchaConfirm(app)
        let error = app.staticTexts["login.captcha.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "图形验证码输入错误！")
        XCTAssertTrue(app.buttons["login.captcha.confirm"].isEnabled)
        capture(app, "captcha-wrong-answer")
        app.buttons["刷新图形验证码"].tap()
        XCTAssertFalse(error.exists)
        answer.tap(); answer.typeText("1234")
        XCTAssertFalse(app.toolbars.buttons["完成"].exists)
        XCTAssertTrue(app.buttons["login.captcha.confirm"].isEnabled)
        tapCaptchaConfirm(app)
        XCTAssertTrue(app.staticTexts["login.notice"].waitForExistence(timeout: 5))
        let code = app.textFields["login.code"]; code.tap(); code.typeText("2468")
        hideKeyboard(app); capture(app, "code-filled")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.account"].label.contains("测试用户"))
    }
    @MainActor func testCredentialReadFailureIsGuestAndCheckoutRequiresLogin() {
        let app = app("success", seed: true)
        XCTAssertTrue(app.buttons["me.account"].label.contains("未登录"))
        app.tabBars.buttons["购物车"].tap()
        let quantity = app.staticTexts["cart.quantity.830001.1"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        app.buttons["cart.plus.830001.1"].tap()
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertTrue(
            NSPredicate(format: "label == %@", "2").evaluate(with: quantity)
                || XCTWaiter.wait(
                    for: [
                        XCTNSPredicateExpectation(
                            predicate: NSPredicate(format: "label == %@", "2"), object: quantity)
                    ], timeout: 5) == .completed
        )
        app.buttons["cart.minus.830001.1"].tap()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label == %@", "1"), object: quantity)
                ], timeout: 5), .completed)
        app.buttons["cart.select.830001.1"].tap()
        app.buttons["cart.checkout"].tap()
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertEqual(quantity.label, "1")
        app.buttons["cart.edit"].tap()
        app.buttons["cart.select.830001.1"].tap()
        app.buttons["cart.delete"].tap()
        XCTAssertTrue(quantity.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.3"].exists)
        capture(app, "guest-cart-deleted")
    }
    @MainActor func testIndependentCartCheckoutLoginReturnsToOriginalStack() {
        let app = app(seed: true)
        app.tabBars.buttons["首页"].tap()
        let card = app.buttons["home.flashSale.830001.card"]
        for _ in 0..<5 { if card.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(card.isHittable); card.tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        app.buttons["detail.openCart"].tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        app.buttons["cart.select.830001.1"].tap()
        app.buttons["cart.checkout"].tap()
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["cart.quantity.830001.3"].exists)
        app.buttons["cart.select.830001.1"].tap(); app.buttons["cart.checkout"].tap()
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5))
        app.buttons["login.choosePassword"].tap()
        phone(app); app.secureTextFields["login.password"].tap()
        app.secureTextFields["login.password"].typeText("test-only"); hideKeyboard(app)
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.staticTexts["checkout.quantity"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["checkout.quantity"].label, "数量：1")
        // Dismiss the observed system AutoFill prompt before exercising native Back.
        for surface in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let prompt = surface.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@ OR label CONTAINS[c] %@", "保存密码", "Save Password")
            ).firstMatch
            if prompt.exists {
                for title in ["以后", "Not Now"] where surface.buttons[title].exists {
                    surface.buttons[title].tap(); break
                }
            }
        }
        XCTAssertFalse(app.tabBars.buttons["首页"].exists)
        app.navigationBars.buttons["BackButton"].tap()
        // The one-time guest purchase input is not a merge into this account's cart.
        XCTAssertTrue(app.staticTexts["cart.empty"].waitForExistence(timeout: 5))
        capture(app, "checkout-login-independent-account-cart")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.account"].label.contains("测试用户"))
    }
    @MainActor func testSystemNotificationPermissionAndForegroundDelivery() {
        let app = app(systemNotification: true)
        app.buttons["me.account"].tap(); app.buttons["login.chooseCode"].tap()
        phone(app); hideKeyboard(app); app.buttons["login.requestCode"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            let allow = alert.buttons["允许"].exists ? alert.buttons["允许"] : alert.buttons["Allow"]
            XCTAssertTrue(allow.exists); allow.tap()
        }
        let answer = app.textFields["login.captcha.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.tap(); answer.typeText("1234"); hideKeyboard(app)
        tapCaptchaConfirm(app)
        XCTAssertTrue(app.staticTexts["login.notice"].waitForExistence(timeout: 5))
        XCTAssertTrue(springboard.staticTexts["青商城登录验证码"].waitForExistence(timeout: 5))
        capture(springboard, "system-local-code-notification")
    }
    @MainActor func testLeavingPendingLoginKeepsGuestIdentity() {
        let app = app("pending")
        app.buttons["me.account"].tap(); app.buttons["login.choosePassword"].tap()
        phone(app); app.secureTextFields["login.password"].tap()
        app.secureTextFields["login.password"].typeText("test-only"); hideKeyboard(app)
        app.buttons["login.submit"].tap()
        XCTAssertFalse(app.buttons["login.submit"].isEnabled)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["me.account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["me.account"].label.contains("未登录"))
        app.buttons["me.account"].tap()
        XCTAssertTrue(app.buttons["login.choosePassword"].waitForExistence(timeout: 5))
    }
    @MainActor func testPasswordFailureRetainsInputAndAllowsRetry() {
        let app = app("passwordFailure")
        app.buttons["me.account"].tap(); app.buttons["login.choosePassword"].tap()
        phone(app); app.secureTextFields["login.password"].tap()
        app.secureTextFields["login.password"].typeText("test-only"); hideKeyboard(app)
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.staticTexts["login.error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["login.phone"].value as? String, "13800000000")
        XCTAssertTrue(app.buttons["login.submit"].isEnabled)
        capture(app, "password-failure")
    }
    @MainActor func testNotificationDeniedCanCancelAndUsePassword() {
        let app = app("notificationDenied")
        app.buttons["me.account"].tap(); app.buttons["login.chooseCode"].tap()
        phone(app); hideKeyboard(app); app.buttons["login.requestCode"].tap()
        XCTAssertTrue(app.staticTexts["login.captcha.error"].waitForExistence(timeout: 5))
        capture(app, "code-permission-denied")
        XCTAssertFalse(app.navigationBars.buttons["取消"].exists)
        let title = app.navigationBars["安全验证"]
        let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: destination)
        XCTAssertTrue(app.staticTexts["login.captcha.error"].waitForNonExistence(timeout: 5))
        app.buttons["使用密码登录"].tap()
        XCTAssertTrue(app.secureTextFields["login.password"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["login.submit"].isEnabled)
    }
    @MainActor func testAccessibilityLayoutKeepsLoginControlsReachable() {
        let app = app(large: true)
        capture(app, "me-accessibility")
        app.swipeUp(); capture(app, "me-accessibility-cards")
        for _ in 0..<3 { if app.buttons["me.account"].isHittable { break }; app.swipeDown() }
        app.buttons["me.account"].tap()
        let password = app.buttons["login.choosePassword"]
        for _ in 0..<5 { if password.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(password.isHittable); password.tap()
        capture(app, "password-accessibility")
        let submit = app.buttons["login.submit"]
        for _ in 0..<5 { if submit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(submit.isHittable)
        capture(app, "password-accessibility-submit")
    }
}
