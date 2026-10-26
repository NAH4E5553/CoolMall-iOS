import XCTest

final class AddressFlowTests: XCTestCase {
    @MainActor private func open(_ scenario: String = "success", large: Bool = false)
        -> XCUIApplication
    {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-banner-manual", "--ui-cart-store",
            UUID().uuidString, "--ui-account-fixture", "success", "--ui-addresses", scenario,
        ]
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch(); XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10));
        app.tabBars.buttons["我的"].tap()
        let entry = app.buttons["me.addresses"]
        for _ in 0..<6 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        let password = app.buttons["login.choosePassword"];
        XCTAssertTrue(password.waitForExistence(timeout: 5)); password.tap()
        let phone = app.textFields["login.phone"];
        XCTAssertTrue(phone.waitForExistence(timeout: 5)); phone.tap();
        phone.typeText("13800000000")
        app.secureTextFields["login.password"].tap();
        app.secureTextFields["login.password"].typeText("test-only")
        let done = app.toolbars.buttons["完成"]; if done.exists { done.tap() }
        let submit = app.buttons["login.submit"]
        for _ in 0..<4 { if submit.isHittable { break }; app.swipeUp() }
        submit.tap(); XCTAssertTrue(app.navigationBars["收货地址"].waitForExistence(timeout: 5))
        for surface in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let later = surface.buttons["以后"]
            if later.exists && later.isHittable { later.tap() }
            let notNow = surface.buttons["Not Now"]
            if notNow.exists && notNow.isHittable { notNow.tap() }
        }
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name;
        image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func node(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor func testGuestLoginResumesListEditUsesSwitchAndSavesThenRefreshes() {
        let app = open(); let edit = app.buttons["addresses.edit.1"];
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        capture(app, "address-list-default-and-add-accent")
        XCTAssertGreaterThanOrEqual(edit.frame.width, 44);
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let contact = app.textFields["address.contact"];
        XCTAssertTrue(contact.waitForExistence(timeout: 5));
        XCTAssertEqual(contact.value as? String, "联系人1")
        let toggle = app.switches["address.default"]; XCTAssertTrue(toggle.exists);
        XCTAssertEqual(toggle.value as? String, "1")
        capture(app, "address-default-switch-enabled-purple"); toggle.tap()
        capture(app, "address-edit-existing-switch")
        let save = app.buttons["address.save"]; XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.buttons["addresses.edit.1"].waitForExistence(timeout: 5));
        app.buttons["addresses.edit.1"].tap()
        XCTAssertTrue(app.switches["address.default"].waitForExistence(timeout: 5));
        XCTAssertEqual(app.switches["address.default"].value as? String, "0")
    }
    @MainActor func testEmptyFormFocusPlaceholdersFixedRegionHeightAndAutomaticFinalSelection() {
        let app = open("empty"); app.buttons["addresses.add"].tap()
        let contact = app.textFields["address.contact"];
        XCTAssertTrue(contact.waitForExistence(timeout: 5));
        XCTAssertFalse(app.buttons["address.save"].isEnabled)
        capture(app, "address-empty-save-disabled-purple")
        contact.tap(); XCTAssertEqual(contact.placeholderValue, "请填写联系人");
        capture(app, "address-contact-focused")
        contact.typeText("测试联系人")
        let phone = app.textFields["address.phone"]; phone.tap();
        XCTAssertEqual(phone.placeholderValue, "请填写手机号"); phone.typeText("1380000000")
        let field = app.buttons["address.region"]; let fieldBottom = field.frame.maxY; field.tap()
        let header = node(app, "address.region.header");
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let top = header.frame.minY
        XCTAssertGreaterThanOrEqual(top, fieldBottom - 1)
        for title in ["关闭", "取消", "完成", "确认"] { XCTAssertFalse(app.buttons[title].exists) }
        app.buttons["address.region.row.130000"].tap();
        XCTAssertEqual(header.frame.minY, top, accuracy: 1)
        app.buttons["address.region.row.130100"].tap();
        XCTAssertEqual(header.frame.minY, top, accuracy: 1)
        capture(app, "address-region-fixed-district-level")
        app.buttons["address.region.row.130104"].tap(); XCTAssertFalse(header.exists)
        XCTAssertTrue(field.label.contains("河北省 石家庄市 桥西区"))
        let detail = app.textFields["address.detail"]; detail.tap();
        XCTAssertEqual(detail.placeholderValue, "请填写街道、楼牌号等"); detail.typeText("测试街道1号")
        let save = app.buttons["address.save"]
        XCTAssertFalse(save.isEnabled)
        let validation = app.staticTexts["address.validation"]
        XCTAssertTrue(validation.waitForExistence(timeout: 3))
        XCTAssertEqual(validation.label, "请填写11位有效手机号")
        capture(app, "address-complete-invalid-phone-disabled")
        phone.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        phone.typeText("0")
        XCTAssertEqual(phone.value as? String, "13800000000")
        XCTAssertFalse(validation.exists); XCTAssertTrue(save.isEnabled)
        capture(app, "address-corrected-phone-enabled")
        save.tap()
        XCTAssertTrue(app.buttons["addresses.edit.1"].waitForExistence(timeout: 5));
        capture(app, "address-added-list")
    }
    @MainActor
    func testRegionListScrollDoesNotDismissHeaderDownAndOutsideDoAndCancelPreservesDraft() {
        let app = open(); app.buttons["addresses.edit.1"].tap()
        let field = app.buttons["address.region"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = field.label; let frame = field.frame
        let outside = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: frame.midX, dy: frame.minY - 16))
        field.tap(); let header = node(app, "address.region.header");
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let top = header.frame.minY
        let rows = app.scrollViews["address.region.rows"]; rows.swipeUp();
        XCTAssertTrue(header.exists); XCTAssertEqual(header.frame.minY, top, accuracy: 1)
        rows.swipeDown(); XCTAssertTrue(header.exists)
        XCTAssertEqual(header.frame.minY, top, accuracy: 1)
        XCTAssertFalse(app.buttons["address.save"].exists)
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(
            forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 38)),
            withVelocity: .slow, thenHoldForDuration: 0.6)
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in header.exists && abs(header.frame.minY - top) <= 1 },
            object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 3), .completed)
        XCTAssertTrue(header.exists); XCTAssertEqual(header.frame.minY, top, accuracy: 1)
        capture(app, "address-region-short-drag-returned")
        start.press(
            forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -40)),
            withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(header.exists); XCTAssertEqual(header.frame.minY, top, accuracy: 1)
        let end = start.withOffset(CGVector(dx: 0, dy: 110))
        start.press(
            forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertFalse(header.exists);
        XCTAssertEqual(field.label, original)
        field.tap(); XCTAssertTrue(header.waitForExistence(timeout: 5));
        app.buttons["address.region.step.0"].tap()
        app.buttons["address.region.row.130000"].tap(); outside.tap()
        XCTAssertFalse(header.exists); XCTAssertEqual(field.label, original)
        field.tap();
        XCTAssertTrue(app.buttons["address.region.row.110101"].waitForExistence(timeout: 5))
        capture(app, "address-region-cancel-restores-beijing")
    }
    @MainActor func testDeleteConfirmationCancelAndConfirmedDeleteThenListRefresh() {
        let app = open(); let button = app.buttons["addresses.delete.1"];
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(button.frame.width, 44);
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let confirmation = app.sheets["确定删除该地址？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        // iOS 27 presents a native compact popover with an outside-dismissal surface.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5)); XCTAssertTrue(button.exists)
        button.tap(); app.buttons["删除"].tap();
        XCTAssertTrue(button.waitForNonExistence(timeout: 5));
        XCTAssertTrue(app.buttons["addresses.edit.2"].exists)
        capture(app, "address-delete-refreshed-list")
    }
    @MainActor func testSaveRejectionPreservesDraftAndExplicitRetryReturnsToList() {
        let app = open("rejection"); app.buttons["addresses.edit.1"].tap()
        let save = app.buttons["address.save"]; XCTAssertTrue(save.waitForExistence(timeout: 5));
        save.tap()
        let error = app.staticTexts["address.error"];
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "地址保存失败");
        XCTAssertEqual(app.textFields["address.contact"].value as? String, "联系人1")
        XCTAssertTrue(save.isEnabled); capture(app, "address-save-rejection-keeps-draft");
        save.tap()
        XCTAssertTrue(app.buttons["addresses.edit.1"].waitForExistence(timeout: 5))
    }
    @MainActor func testUnknownSaveKeepsDraftAndDisablesReplayWithoutExtraButtons() {
        let app = open("unknown"); app.buttons["addresses.edit.1"].tap()
        let save = app.buttons["address.save"]; XCTAssertTrue(save.waitForExistence(timeout: 5));
        save.tap()
        let error = app.staticTexts["address.error"];
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("尚未确认")); XCTAssertFalse(save.isEnabled)
        XCTAssertEqual(app.textFields["address.contact"].value as? String, "联系人1")
        for title in ["取消", "完成", "关闭", "重试"] { XCTAssertFalse(app.buttons[title].exists) }
        capture(app, "address-unknown-save-no-replay")
    }
    @MainActor func testListLoadsMoreWhenLastCardBecomesVisible() {
        let app = open(); let last = app.buttons["addresses.edit.12"]
        for _ in 0..<6 {
            if last.exists && last.isHittable { break }; app.scrollViews["addresses.list"].swipeUp()
        }
        XCTAssertTrue(last.isHittable); capture(app, "address-second-page-visible")
    }
    @MainActor func testLargeTextRegionRemainsBelowFieldAndRowsAreScrollable() {
        let app = open("success", large: true); app.buttons["addresses.add"].tap()
        let field = app.buttons["address.region"]
        for _ in 0..<5 { if field.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(field.isHittable); let fieldBottom = field.frame.maxY; field.tap();
        let header = node(app, "address.region.header");
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(header.frame.minY, fieldBottom - 1)
        let rows = app.scrollViews["address.region.rows"]; rows.swipeUp();
        XCTAssertTrue(header.exists)
        capture(app, "address-region-large-text")
    }
}
