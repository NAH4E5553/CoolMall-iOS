import XCTest

final class SearchFlowTests: XCTestCase {
    @MainActor private func launch(
        _ mode: String = "valid", large: Bool = false, login: Bool = false,
        homeMode: String = "valid", categoryFixture: Bool = false
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", homeMode, "--ui-banner-manual", "--ui-search-fixture", mode,
            "--ui-product-detail-fixture", "valid", "--ui-cart-store", UUID().uuidString,
        ]
        if categoryFixture { app.launchArguments += ["--ui-category-fixture", "valid"] }
        if mode.hasPrefix("history-") { app.launchArguments += ["--ui-search-history-seed"] }
        if login {
            app.launchArguments += ["--ui-account-fixture", "success", "--ui-orders", "valid"]
        }
        if large {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch(); return app
    }
    @MainActor private func open(_ app: XCUIApplication) {
        let button = app.buttons["home.search"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        XCTAssertTrue(app.textFields["search.input"].waitForExistence(timeout: 5))
    }
    @MainActor private func search(_ app: XCUIApplication, _ text: String) {
        let input = app.textFields["search.input"]; input.tap(); input.typeText(text)
        app.buttons["search.submit"].tap()
    }
    @MainActor private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name;
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func openFeatured(_ app: XCUIApplication) {
        let all = app.buttons["home.section.flashSale.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        for _ in 0..<4 {
            if all.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(all.isHittable); all.tap()
        XCTAssertTrue(app.buttons["search.filter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["限时精选"].exists)
    }
    @MainActor func testAllTenHomeCategoriesOpenTheirOwnResultsAndReturnHome() {
        let app = launch("entry-categories")
        let firstChildren = [1, 8, 10, 14, 17, 20, 23, 27, 30, 32]
        for index in 0..<10 {
            let category = app.buttons["home.category.\(800001 + index)"]
            XCTAssertTrue(category.waitForExistence(timeout: 10))
            for _ in 0..<3 { if category.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(category.isHittable); category.tap()
            XCTAssertTrue(
                app.buttons["search.product.\(830000 + firstChildren[index])"].waitForExistence(
                    timeout: 5))
            let input = app.textFields["search.input"]
            XCTAssertTrue(
                (input.value as? String) == "" || (input.value as? String) == input.placeholderValue
            )
            back(app)
            XCTAssertTrue(app.buttons["home.search"].waitForExistence(timeout: 5))
        }
        open(app)
        XCTAssertFalse(app.buttons["search.history.手机"].exists)
    }

    @MainActor func testHomeAllGoodsLoadsBeyondPreviewAndKeepsProductsAfterDetailReturn() {
        let app = launch()
        XCTAssertFalse(app.buttons["home.goods.more"].exists)
        let last = app.buttons["home.goods.830013.card"]
        for _ in 0..<16 { if last.exists && last.isHittable { break }; app.swipeUp() }
        for _ in 0..<6 { if last.exists && last.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home.goods.end"].exists)
        last.tap(); XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home.goods.end"].exists)
    }

    @MainActor func testPagedHomeRetainsGoodsAcrossTabsAndRetapRefreshesSamePage() {
        let app = launch(homeMode: "retap-sequence", categoryFixture: true)
        XCTAssertFalse(app.buttons["home.goods.more"].exists)
        let last = app.buttons["home.goods.830013.card"]
        for _ in 0..<16 { if last.exists && last.isHittable { break }; app.swipeUp() }
        for _ in 0..<6 { if last.exists && last.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        let beforeY = last.frame.minY
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(app.buttons["category.root.800001"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertEqual(last.frame.minY, beforeY, accuracy: 1)
        XCTAssertTrue(app.staticTexts["home.goods.end"].exists)
        app.tabBars.buttons["首页"].tap()
        // The controlled home source adds one item on the real refresh. This proves the
        // refresh was consumed with a goods pager installed, not just a Tab switch.
        let refreshedCount = expectation(
            for: NSPredicate(format: "label == %@", "全部商品：11"),
            evaluatedWith: app.staticTexts["home.count.goods"])
        wait(for: [refreshedCount], timeout: 5)
        XCTAssertTrue(app.buttons["home.category.800001"].isHittable)
        XCTAssertFalse(app.staticTexts["home.goods.end"].exists)
    }

    @MainActor func testHomeFeaturedUsesResultsPagingSortAndReturnsThroughSameSource() {
        let app = launch(); openFeatured(app)
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        capture(app, "featured-results-header")
        let pageTwo = app.buttons["search.product.830011"]
        for _ in 0..<4 {
            if pageTwo.exists && pageTwo.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(pageTwo.waitForExistence(timeout: 5))
        capture(app, "featured-results-page-two")
        app.buttons["search.layout"].tap()
        app.buttons["search.sort.sales"].tap()
        let lastFeatured = app.buttons["search.product.830011"]
        XCTAssertTrue(lastFeatured.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.product.830013"].exists)
        lastFeatured.tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(lastFeatured.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.product.830013"].exists)
        XCTAssertFalse(app.staticTexts["限时精选"].exists)
        XCTAssertEqual(app.buttons["search.layout"].label, "切换双列")
        back(app)
        XCTAssertTrue(app.buttons["home.section.flashSale.all"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["search.input"].exists)
        open(app)
        XCTAssertFalse(app.buttons["search.history.限时精选"].exists)
        capture(app, "search-discovery-white-header")
    }
    @MainActor func testFeaturedFailureRetryAndEmptyKeywordReturnKeepScope() {
        let app = launch("retry"); openFeatured(app)
        let retry = app.buttons["search.resultsRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        search(app, "无结果")
        XCTAssertTrue(app.staticTexts["暂无匹配商品"].waitForExistence(timeout: 5))
        let input = app.textFields["search.input"]; input.tap()
        input.press(forDuration: 1.1)
        let selectAll = app.menuItems["全选"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3)); selectAll.tap()
        input.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(
            (input.value as? String) == "" || (input.value as? String) == input.placeholderValue)
        app.buttons["search.submit"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["限时精选"].exists)
        app.buttons["search.sort.sales"].tap()
        XCTAssertTrue(app.buttons["search.product.830011"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.product.830013"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "featured-cleared-keyword")
        back(app)
        XCTAssertTrue(app.buttons["home.section.flashSale.all"].waitForExistence(timeout: 5))
    }
    @MainActor func testHistoryPersistsAcrossRestartAndReturnsToOriginalHome() {
        let app = launch(); open(app)
        capture(app, "search-discovery-header")
        app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        back(app)
        XCTAssertTrue(app.buttons["search.history.Xiaomi 17"].waitForExistence(timeout: 5));
        capture(app, "search-history")
        app.terminate(); app.launch(); open(app)
        XCTAssertTrue(app.buttons["search.history.Xiaomi 17"].waitForExistence(timeout: 5))
        back(app); XCTAssertTrue(app.buttons["home.search"].waitForExistence(timeout: 5))
    }
    @MainActor func testClearHistoryCanCancelAndConfirmWithoutRemovingRecommendations() {
        let app = launch(); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5)); back(app)
        app.buttons["search.clear"].tap();
        app.alerts["清空搜索历史？"].buttons.matching(identifier: "search.cancelClear").firstMatch.tap()
        XCTAssertTrue(app.buttons["search.history.Xiaomi 17"].exists)
        app.buttons["search.clear"].tap()
        app.alerts["清空搜索历史？"].buttons.matching(identifier: "search.confirmClear").firstMatch.tap()
        XCTAssertTrue(app.buttons["search.history.Xiaomi 17"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.keyword.Xiaomi 17"].exists);
        capture(app, "search-cleared")
    }
    @MainActor func testSalesSortLayoutAndRealDetailReturnKeepQuery() {
        let app = launch(); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        capture(app, "search-results-header")
        app.buttons["search.sort.sales"].tap()
        XCTAssertEqual(app.buttons["search.sort.sales"].value as? String, "从低到高")
        XCTAssertTrue(app.buttons["search.product.830013"].waitForExistence(timeout: 5))
        app.buttons["search.layout"].tap(); capture(app, "search-single-column-sales")
        app.buttons["search.product.830013"].tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["search.product.830013"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["search.input"].value as? String, "Xiaomi 17")
        let layout = app.buttons["search.layout"]
        XCTAssertEqual(layout.label, "切换双列"); layout.tap()
        XCTAssertEqual(layout.label, "切换单列")
        let first = app.buttons["search.product.830013"]
        let second = app.buttons["search.product.830012"]
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(abs(first.frame.minX - second.frame.minX), 20)
        app.buttons["search.sort.price"].tap();
        XCTAssertEqual(app.buttons["search.sort.price"].value as? String, "从低到高")
        app.buttons["search.sort.price"].tap();
        XCTAssertEqual(app.buttons["search.sort.price"].value as? String, "从高到低")
        let input = app.textFields["search.input"]; input.tap(); input.press(forDuration: 1.1)
        let selectAll = app.menuItems["全选"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3)); selectAll.tap()
        input.typeText("无结果"); app.buttons["search.submit"].tap()
        XCTAssertTrue(app.staticTexts["暂无匹配商品"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "results-toolbar-actions-after-detail-return")
    }
    @MainActor func testFiltersCancelDraftThenApplyCategoryAndPrice() {
        let app = launch(); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        app.buttons["search.filter"].tap()
        XCTAssertTrue(app.buttons["search.category.2"].waitForExistence(timeout: 5));
        capture(app, "search-filter")
        app.buttons["search.category.2"].tap()
        app.textFields["search.minimum"].tap(); app.textFields["search.minimum"].typeText("500")
        app.buttons["search.filterClose"].tap(); app.buttons["search.filter"].tap()
        XCTAssertEqual(app.textFields["search.minimum"].value as? String, "最低价")
        app.buttons["search.category.2"].tap()
        app.textFields["search.minimum"].tap(); app.textFields["search.minimum"].typeText("500")
        app.buttons["search.filterApply"].tap()
        XCTAssertTrue(app.buttons["search.product.830006"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.product.830001"].exists)
    }
    @MainActor func testFilterInvalidRangeStaysOpenAndResetRequiresConfirm() {
        let app = launch(); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5));
        app.buttons["search.filter"].tap()
        app.textFields["search.minimum"].tap(); app.textFields["search.minimum"].typeText("900")
        app.textFields["search.maximum"].tap(); app.textFields["search.maximum"].typeText("100")
        app.buttons["search.filterApply"].tap()
        XCTAssertTrue(app.staticTexts["search.filterError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["search.filterReset"].tap()
        XCTAssertTrue(app.staticTexts["search.filterError"].waitForNonExistence(timeout: 5))
        for id in ["search.minimum", "search.maximum"] {
            let field = app.textFields[id]
            XCTAssertTrue(
                (field.value as? String) == "" || (field.value as? String) == field.placeholderValue
            )
        }
        XCTAssertTrue(app.buttons["search.filterApply"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "search-filter-reset")
        app.buttons["search.filterApply"].tap()
        XCTAssertTrue(app.buttons["search.filterApply"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
    }
    @MainActor func testSearchFailureRetryAndEmptyResultAreDistinct() {
        let app = launch("retry"); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        let retry = app.buttons["search.resultsRetry"];
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        let input = app.textFields["search.input"]; input.tap()
        input.press(forDuration: 1.1)
        if app.menuItems["全选"].exists {
            app.menuItems["全选"].tap(); input.typeText("无结果")
        } else {
            input.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Xiaomi 17".count));
            input.typeText("无结果")
        }
        app.buttons["search.submit"].tap()
        XCTAssertTrue(app.staticTexts["暂无匹配商品"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "search-empty")
        let rebuiltInput = app.textFields["search.input"]; rebuiltInput.tap()
        rebuiltInput.press(forDuration: 1.1)
        let selectAll = app.menuItems["全选"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3)); selectAll.tap()
        rebuiltInput.typeText("手机"); app.buttons["search.submit"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["search.input"].value as? String, "手机")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
    @MainActor func testLoginFromDetailPreservesEditedQuerySortLayoutAndProducts() {
        let app = launch(login: true)
        addUIInterruptionMonitor(withDescription: "Synthetic password save") { alert in
            guard
                alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "保存密码"))
                    .firstMatch.exists,
                alert.buttons["以后"].exists
            else { return false }
            alert.buttons["以后"].tap(); return true
        }
        open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        let input = app.textFields["search.input"]; input.tap()
        input.press(forDuration: 1.1)
        let selectAll = app.menuItems["全选"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3)); selectAll.tap()
        input.typeText("手机"); app.buttons["search.submit"].tap()
        XCTAssertEqual(input.value as? String, "手机")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["search.sort.sales"].tap(); app.buttons["search.layout"].tap()
        let product = app.buttons["search.product.830013"];
        XCTAssertTrue(product.waitForExistence(timeout: 5)); product.tap()
        XCTAssertTrue(app.buttons["detail.buyNow"].waitForExistence(timeout: 5));
        app.buttons["detail.buyNow"].tap()
        let sku = app.buttons["detail.spec.1"]; XCTAssertTrue(sku.waitForExistence(timeout: 5));
        sku.tap()
        app.buttons["detail.spec.buyNow"].tap()
        let choose = app.buttons["login.choosePassword"];
        XCTAssertTrue(choose.waitForExistence(timeout: 5)); choose.tap()
        let phone = app.textFields["login.phone"]; phone.tap(); phone.typeText("13800000000")
        let secret = app.secureTextFields["login.password"]; secret.tap();
        secret.typeText("test-only")
        if app.toolbars.buttons["完成"].exists { app.toolbars.buttons["完成"].tap() }
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.staticTexts["checkout.quantity"].waitForExistence(timeout: 5))
        for surface in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            if surface.buttons["以后"].exists
                && surface.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "保存密码"))
                    .firstMatch.exists
            {
                surface.buttons["以后"].tap()
            }
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5));
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.buttons["search.product.830013"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["search.input"].value as? String, "手机")
        XCTAssertEqual(app.buttons["search.layout"].label, "切换双列")
        XCTAssertEqual(app.buttons["search.sort.sales"].value as? String, "从低到高")
        capture(app, "search-login-return")
    }
    @MainActor func testFilterContentScrollKeepsHeaderFooterAndCancelAvailable() {
        let app = launch(); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.filter"].waitForExistence(timeout: 5));
        app.buttons["search.filter"].tap()
        let close = app.buttons["search.filterClose"]; let apply = app.buttons["search.filterApply"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let headerY = close.frame.midY; let footerY = apply.frame.midY
        let scroll = app.scrollViews["search.filterContent"]
        scroll.swipeUp(); scroll.swipeUp()
        XCTAssertTrue(close.isHittable && apply.isHittable)
        XCTAssertEqual(close.frame.midY, headerY, accuracy: 1)
        XCTAssertEqual(apply.frame.midY, footerY, accuracy: 1)
        capture(app, "search-filter-scrolled"); close.tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
    }
    @MainActor func testFocusedDiscoveryCanSubmitHotKeywordAndHistoryWithoutLosingDraft() {
        let app = launch(); open(app)
        let input = app.textFields["search.input"]; input.tap(); input.typeText("手机")
        app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["search.input"].value as? String, "Xiaomi 17")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        back(app)
        XCTAssertEqual(app.textFields["search.input"].value as? String, "手机")
        app.textFields["search.input"].tap(); app.buttons["search.history.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["search.input"].value as? String, "Xiaomi 17")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
    @MainActor func testKeyboardSubmitDismissesAndEdgeSwipeReturnsToDiscovery() {
        let app = launch(); open(app)
        let input = app.textFields["search.input"]
        input.tap(); input.typeText("手机\n")
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "search-keyboard-submit")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.buttons["search.history.手机"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.keyword.Xiaomi 17"].exists)
    }
    @MainActor func testHotFailureStillAllowsManualSearchWithLargeText() {
        let app = launch("hot-error", large: true); open(app)
        XCTAssertTrue(app.buttons["search.keywordsRetry"].waitForExistence(timeout: 5))
        search(app, "手机")
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5));
        capture(app, "search-large-text")
    }
    @MainActor private func middleProduct(_ app: XCUIApplication) throws -> XCUIElement {
        let scroll = app.scrollViews["search.results"]
        for _ in 0..<3 { scroll.swipeUp(velocity: .slow) }
        func descendants(_ node: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            [node] + node.children.flatMap { descendants($0) }
        }
        let nodes = descendants(try app.snapshot())
        let viewport = try XCTUnwrap(nodes.first { $0.identifier == "search.results" }).frame
        let complete = nodes.filter {
            $0.elementType == .button && $0.identifier.hasPrefix("search.product.")
                && $0.frame.height > 44 && viewport.insetBy(dx: 0, dy: 8).contains($0.frame)
        }.sorted {
            if abs($0.frame.minY - $1.frame.minY) < 1 { return $0.frame.minX < $1.frame.minX }
            return $0.frame.minY < $1.frame.minY
        }
        let identifier = try XCTUnwrap(complete.first).identifier
        let item = app.buttons[identifier]
        XCTAssertEqual(item.identifier, identifier)
        let id = try XCTUnwrap(
            Int64(item.identifier.replacingOccurrences(of: "search.product.", with: "")))
        XCTAssertGreaterThan(id, 830006); XCTAssertLessThan(id, 830045)
        XCTAssertTrue(item.isHittable)
        let note = XCTAttachment(
            string: "anchor=\(item.identifier) frame=\(item.frame) viewport=\(viewport)")
        note.name = "middle-anchor"; note.lifetime = .keepAlways; add(note)
        return item
    }
    @MainActor private func expectVisible(_ item: XCUIElement, in scroll: XCUIElement) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
        XCTAssertGreaterThan(item.frame.intersection(scroll.frame).height, 44)
    }
    @MainActor func testMiddleListDetailReturnPreservesVisibleItemAndOffset() throws {
        let app = launch("long"); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        let item = try middleProduct(app); let before = item.frame.minY
        capture(app, "middle-detail-before"); item.tap()
        XCTAssertTrue(app.buttons["detail.back"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        expectVisible(item, in: app.scrollViews["search.results"])
        capture(app, "middle-detail-after")
        XCTAssertEqual(item.frame.minY, before, accuracy: 2)
        XCTAssertEqual(app.textFields["search.input"].value as? String, "Xiaomi 17")
    }
    @MainActor func testMiddleListColumnRoundTripKeepsAnchorVisible() throws {
        let app = launch("long"); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        let item = try middleProduct(app); let scroll = app.scrollViews["search.results"]
        capture(app, "middle-grid-before"); app.buttons["search.layout"].tap()
        expectVisible(item, in: scroll); capture(app, "middle-single-after")
        XCTAssertEqual(app.buttons["search.layout"].label, "切换双列")
        app.buttons["search.layout"].tap(); expectVisible(item, in: scroll)
        capture(app, "middle-grid-return")
        XCTAssertFalse(app.buttons["search.product.830001"].isHittable)
    }
    @MainActor func testMiddleListSortAndFilterRestartAtFirstPage() throws {
        let app = launch("long"); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        _ = try middleProduct(app); capture(app, "middle-sort-before")
        app.buttons["search.sort.price"].tap()
        let first = app.buttons["search.product.830001"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); capture(app, "middle-sort-after")
        expectVisible(first, in: app.scrollViews["search.results"])
        XCTAssertEqual(
            first.frame.minY, app.scrollViews["search.results"].frame.minY + 12, accuracy: 2)
        _ = try middleProduct(app); capture(app, "middle-filter-before")
        app.buttons["search.filter"].tap()
        let minimum = app.textFields["search.minimum"]; minimum.tap(); minimum.typeText("1000")
        app.buttons["search.filterApply"].tap()
        let filtered = app.buttons["search.product.830011"]
        XCTAssertTrue(filtered.waitForExistence(timeout: 5))
        expectVisible(filtered, in: app.scrollViews["search.results"])
        XCTAssertEqual(
            filtered.frame.minY, app.scrollViews["search.results"].frame.minY + 12, accuracy: 2)
        XCTAssertEqual(app.buttons["search.sort.price"].value as? String, "从低到高")
        capture(app, "middle-filter-restart")
    }
    @MainActor func testHotEmptyKeepsManualSearchAndRecordedHistoryAvailable() {
        let app = launch("hot-empty"); open(app)
        XCTAssertTrue(app.staticTexts["暂无推荐搜索"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.keywordsRetry"].exists)
        search(app, "手机")
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        back(app)
        XCTAssertTrue(app.buttons["search.history.手机"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["暂无推荐搜索"].exists); capture(app, "hot-empty-with-history")
    }
    @MainActor func testHotKeywordFailureExplicitRetryRecovers() {
        let app = launch("hot-retry"); open(app)
        let retry = app.buttons["search.keywordsRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); capture(app, "hot-failure")
        XCTAssertTrue(app.textFields["search.input"].isHittable); retry.tap()
        XCTAssertTrue(app.buttons["search.keyword.Xiaomi 17"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
    }
    @MainActor func testCategoryFailureRetryRestoresSelectableFilters() {
        let app = launch("category-retry"); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        app.buttons["search.filter"].tap()
        let retry = app.buttons["search.categoryRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); capture(app, "category-failure");
        retry.tap()
        XCTAssertTrue(app.buttons["search.category.2"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists); app.buttons["search.category.2"].tap()
        XCTAssertTrue(app.buttons["search.category.2"].isSelected)
        app.buttons["search.filterApply"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        app.buttons["search.filter"].tap()
        XCTAssertTrue(app.buttons["search.category.2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.category.2"].isSelected)
        XCTAssertFalse(retry.exists); capture(app, "category-recovered");
        app.buttons["search.filterClose"].tap()
    }
    @MainActor func testRefreshFailureKeepsOldCardsAndExplicitRetryUpdatesSnapshot() {
        let app = launch("refresh-retry"); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        let first = app.buttons["search.product.830001"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["search.results"]
        capture(app, "refresh-before-pull")
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(
            forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let retry = app.buttons["search.resultsRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(first.exists); XCTAssertFalse(first.label.contains("已刷新"))
        capture(app, "refresh-failure-old-items"); retry.tap()
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "已刷新"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        XCTAssertFalse(retry.exists); capture(app, "refresh-recovered")
    }
    @MainActor func testAppendFailureKeepsFirstPageAndExplicitRetryLoadsSecondPage() {
        let app = launch("append-retry"); open(app); app.buttons["search.keyword.Xiaomi 17"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5))
        let more = app.buttons["search.more"]
        for _ in 0..<5 {
            if more.exists && more.isHittable && more.label == "重试加载" { break }
            app.scrollViews["search.results"].swipeUp(velocity: .slow)
        }
        XCTAssertTrue(more.isHittable); XCTAssertEqual(more.label, "重试加载")
        XCTAssertTrue(app.buttons["search.product.830010"].exists)
        XCTAssertFalse(app.buttons["search.product.830011"].exists)
        capture(app, "append-failure-page-one"); more.tap()
        let second = app.buttons["search.product.830011"]
        for _ in 0..<2 {
            if second.exists && second.isHittable { break }
            app.scrollViews["search.results"].swipeUp(velocity: .slow)
        }
        XCTAssertTrue(second.waitForExistence(timeout: 5)); XCTAssertTrue(second.isHittable)
        capture(app, "append-recovered-page-two")
    }
    @MainActor func testHistoryReadFailureExplicitRetryRestoresStoredHistory() {
        let app = launch("history-read-retry"); open(app)
        let retry = app.buttons["search.historyRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.keyword.Xiaomi 17"].exists);
        capture(app, "history-read-failure")
        retry.tap()
        XCTAssertTrue(app.buttons["search.history.已有历史"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists); capture(app, "history-read-recovered")
        app.launchArguments.removeAll { $0 == "--ui-search-history-seed" }
        app.terminate(); app.launch(); open(app)
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.buttons["search.history.已有历史"].waitForExistence(timeout: 5))
        capture(app, "history-read-restart-recovered")
    }
    @MainActor func testHistoryWriteFailureStillSearchesThenRetryPersistsAcrossRestart() {
        let app = launch("history-write-retry"); open(app)
        XCTAssertTrue(app.buttons["search.history.已有历史"].waitForExistence(timeout: 5))
        search(app, "手机")
        XCTAssertTrue(app.staticTexts["搜索历史未保存"].waitForExistence(timeout: 5))
        capture(app, "history-write-failure-result")
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5)); back(app)
        XCTAssertFalse(app.buttons["search.history.手机"].exists)
        XCTAssertTrue(app.buttons["search.history.已有历史"].exists)
        XCTAssertEqual(app.textFields["search.input"].value as? String, "手机")
        app.buttons["search.submit"].tap()
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5)); back(app)
        XCTAssertTrue(app.buttons["search.history.手机"].waitForExistence(timeout: 5))
        app.launchArguments.removeAll { $0 == "--ui-search-history-seed" }
        app.terminate(); app.launch(); open(app)
        XCTAssertTrue(app.buttons["search.history.手机"].waitForExistence(timeout: 5))
        capture(app, "history-write-restart")
    }
    @MainActor func testHistoryClearFailureKeepsOldHistoryAndRetryPersistsEmpty() {
        let app = launch("history-clear-retry"); open(app)
        XCTAssertTrue(app.buttons["search.history.已有历史"].waitForExistence(timeout: 5))
        app.buttons["search.clear"].tap()
        app.alerts["清空搜索历史？"].buttons.matching(identifier: "search.confirmClear").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["搜索历史清空失败，请重试"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.history.已有历史"].exists);
        capture(app, "history-clear-failure")
        app.buttons["search.clear"].tap()
        app.alerts["清空搜索历史？"].buttons.matching(identifier: "search.confirmClear").firstMatch.tap()
        XCTAssertTrue(app.buttons["search.history.已有历史"].waitForNonExistence(timeout: 5))
        app.launchArguments.removeAll { $0 == "--ui-search-history-seed" }
        app.terminate(); app.launch(); open(app)
        search(app, "磁盘探针")
        XCTAssertTrue(app.buttons["search.product.830001"].waitForExistence(timeout: 5)); back(app)
        XCTAssertTrue(app.buttons["search.history.磁盘探针"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.history.已有历史"].exists)
        XCTAssertTrue(app.buttons["search.keyword.Xiaomi 17"].exists)
        capture(app, "history-clear-restart")
    }

}
