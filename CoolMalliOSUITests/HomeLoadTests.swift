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

    /// A seeded route tests the real home root's navigation appearance;
    /// this is controlled structure evidence, not a new product route.
    @MainActor func testHomeTopRowRemovedAndPushedRouteBackRestoresRoot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-home-fixture", "valid", "--uitest-nav-control", "--uitest-nav-paths", "home=cart",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["cart.fixture"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["home.about"].exists)
        XCTAssertFalse(app.buttons["home.project"].exists)
        let search = app.buttons["home.search"]
        XCTAssertTrue(search.isHittable)
        XCTAssertEqual(
            search.frame.minY, app.staticTexts["home.source"].frame.maxY + 4, accuracy: 1,
            "search follows the existing source marker without a navigation row")
        keepFeedbackScreenshot(app, name: "HOME-top-row-removed-after-back")
        app.buttons["navctl.select.category"].tap()
        XCTAssertTrue(app.staticTexts["category.pending"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        app.buttons["navctl.select.home"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["home.about"].exists)
        XCTAssertFalse(app.buttons["home.project"].exists)
        XCTAssertTrue(search.isHittable)
        keepFeedbackScreenshot(app, name: "HOME-top-row-removed-after-controlled-tab-return")
    }

    @MainActor func testEmptyFixtureShowsCountsAndRetryStaysEmpty() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "empty"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.empty"].label, "首页暂无内容")
        XCTAssertTrue(app.buttons["home.retry"].isHittable)
        keepFeedbackScreenshot(app, name: "HOME03-empty")
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
        XCTAssertEqual(app.staticTexts["home.error"].label, "首页加载失败，请重试")
        XCTAssertEqual(app.staticTexts["home.error.reason"].label, "网络不可用")
        XCTAssertTrue(app.buttons["home.retry"].isHittable)
        keepFeedbackScreenshot(app, name: "HOME03-first-failure")
        app.buttons["home.retry"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.count.flashSale"].label, "限时精选：1")
    }

    @MainActor private func keepFeedbackScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Reach the same auxiliary row through the actual vertical viewport.
    /// A stalled gesture stops the driver; the caller still asserts reachability.
    @MainActor private func reachAuxiliaryRow(
        _ app: XCUIApplication, row: XCUIElement, maximumDrags: Int
    ) {
        if row.exists && row.isHittable { return }
        let scroll = app.scrollViews["home.scroll"]
        let frame = scroll.frame.intersection(app.frame)
        let top = frame.minY
        let bottom = min(frame.maxY, app.tabBars.firstMatch.frame.minY)
        guard !frame.isNull, frame.width > 0, bottom > top else {
            XCTFail("home.scroll has no usable vertical viewport: \(frame)")
            return
        }
        let viewport = CGRect(
            x: frame.minX, y: top, width: frame.width, height: bottom - top)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        // In these two settled fixture flows, the initial touch stays inside
        // the scroll region across title collapse and the observed HUD layout.
        // The right-side content padding avoids nested horizontal cards.
        let x = viewport.minX + viewport.width * 0.98
        let start = origin.withOffset(
            CGVector(dx: x, dy: viewport.minY + viewport.height * 0.9))
        // Keep both endpoints inside the actual scroll viewport, including
        // the DEBUG layout that reserves space above it.
        let end = origin.withOffset(
            CGVector(dx: x, dy: viewport.minY + viewport.height * 0.1))
        var before = row.frame.minY
        var stalledDrags = 0
        for index in 0..<maximumDrags {
            if index > 0, row.exists && row.isHittable { return }
            start.press(
                forDuration: 0.01, thenDragTo: end, withVelocity: 10_000,
                thenHoldForDuration: 0)
            let after = row.frame.minY
            print("home.scroll drag \(index + 1): viewport=\(viewport), rowY=\(before)→\(after)")
            stalledDrags = after < before - 1 ? 0 : stalledDrags + 1
            if stalledDrags == 2 { return }
            before = after
        }
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
    /// through to the real HTTP service. One launch per test method
    /// (CHANGE-04): a three-launch loop exceeded CI's 60s per-test allowance.
    private func assertIllegalArgumentsStopWithConfigError(_ arguments: [String]) {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(
            app.staticTexts["home.testConfigError"].waitForExistence(timeout: 10),
            "expected config error for \(arguments)")
        XCTAssertFalse(app.staticTexts["home.loaded"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["home.error"].waitForExistence(timeout: 2))
    }

    @MainActor func testMissingFixtureValueStopsWithConfigError() {
        assertIllegalArgumentsStopWithConfigError(["--ui-home-fixture"])
    }

    @MainActor func testFlagLikeNextArgumentStopsWithConfigError() {
        assertIllegalArgumentsStopWithConfigError(["--ui-home-fixture", "--uitest-nav-fixture"])
    }

    @MainActor func testUnknownFixtureValueStopsWithConfigError() {
        assertIllegalArgumentsStopWithConfigError(["--ui-home-fixture", "bogus"])
    }
}

/// HOME-02 section-skeleton coverage (AT-HOME-02-01…04). Ordering assertions
/// compare real content/header anchors; empty-section hiding is structural
/// (the elements never exist).
extension HomeLoadTests {
    @MainActor private func revealSectionContent(_ app: XCUIApplication, key: String) {
        for _ in 0..<12 {
            if sectionContent(app, key: key).exists { return }
            app.swipeUp(velocity: .fast)
        }
    }

    /// Real content replaces each former placeholder without weakening its
    /// nonempty/empty section condition. Source-specific leaf IDs stay visible.
    @MainActor private func sectionContent(_ app: XCUIApplication, key: String) -> XCUIElement {
        if key == "banner" {
            return app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "home.banner.current.")
            ).firstMatch
        }
        let prefix = "home.\(key)."
        return app.staticTexts.matching(
            NSPredicate(
                format:
                    "identifier BEGINSWITH %@ AND (identifier ENDSWITH %@ OR identifier ENDSWITH %@)",
                prefix, ".title", ".name")
        ).firstMatch
    }

    private static let orderedSections: [(key: String, title: String)] = [
        ("banner", "轮播"), ("coupon", "优惠券"), ("category", "分类"),
        ("flashSale", "限时精选"), ("recommend", "推荐商品"), ("goods", "全部商品"),
    ]

    /// AT-HOME-02-01: valid input shows all six sections in PRD-015 order.
    @MainActor func testValidFixtureShowsSixSectionsInPRDOrder() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "valid"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.source"].label, "工程夹具（valid）")
        // All six sections retain real content; only product headings remain.
        for section in Self.orderedSections {
            XCTAssertEqual(
                app.staticTexts["home.section.\(section.key).title"].exists,
                !["banner", "coupon", "category"].contains(section.key),
                "only product section headings remain")
            if section.key == "banner" {
                XCTAssertTrue(
                    app.staticTexts["home.banner.page"].exists,
                    "banner must show the real manual carousel for valid input")
            } else {
                revealSectionContent(app, key: section.key)
                XCTAssertTrue(
                    sectionContent(app, key: section.key).exists,
                    "\(section.key) placeholder must exist for valid input")
            }
        }
        // Read through the whole content (last row reachable), then verify the
        // PRD-015 order by frame positions — viewport-independent, unlike a
        // first-hittable recording that degenerates when everything fits.
        let lastRow = app.staticTexts["home.count.categoryAll"]
        for _ in 0..<10 {
            if lastRow.exists, lastRow.isHittable { break }
            app.swipeUp(velocity: .slow)
            usleep(400_000)
        }
        XCTAssertTrue(lastRow.isHittable, "auxiliary last row must be reachable")
        let titleFrames = Self.orderedSections.map { section in
            ["banner", "coupon", "category"].contains(section.key)
                ? sectionContent(app, key: section.key).frame
                : app.staticTexts["home.section.\(section.key).title"].frame
        }
        for index in 1..<titleFrames.count {
            XCTAssertLessThan(
                titleFrames[index - 1].minY, titleFrames[index].minY,
                "\(Self.orderedSections[index - 1].key) must sit above \(Self.orderedSections[index].key)"
            )
        }
        // Left alignment at the shared 16pt margin: product heading leading edges
        // line up regardless of text length.
        let leading = titleFrames[3].minX
        for (index, frame) in titleFrames.enumerated() where index >= 3 {
            XCTAssertEqual(
                frame.minX, leading, accuracy: 2,
                "\(Self.orderedSections[index].key) title must share the left margin")
        }
    }

    /// AT-HOME-02-02: layout-mixed hides the two empty sections entirely and
    /// shows only coupon → flashSale → recommend → goods.
    @MainActor func testLayoutMixedHidesEmptySectionsAndKeepsCounts() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "layout-mixed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.source"].label, "工程夹具（layout-mixed）")
        for key in ["banner", "category"] {
            XCTAssertFalse(
                app.staticTexts["home.section.\(key).title"].exists,
                "\(key) is empty and its title must be hidden")
            XCTAssertFalse(
                sectionContent(app, key: key).exists,
                "\(key) placeholder and reserved area must be hidden")
        }
        for key in ["coupon", "flashSale", "recommend", "goods"] {
            XCTAssertEqual(app.staticTexts["home.section.\(key).title"].exists, key != "coupon")
            revealSectionContent(app, key: key)
            XCTAssertTrue(sectionContent(app, key: key).exists)
        }
        // The counts come from the same snapshot — each visible section has
        // its own non-zero count, hidden ones zero.
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：0")
        XCTAssertEqual(app.staticTexts["home.count.coupon"].label, "优惠券：1")
        XCTAssertEqual(app.staticTexts["home.count.category"].label, "分类：0")
        XCTAssertEqual(app.staticTexts["home.count.flashSale"].label, "限时精选：1")
        XCTAssertEqual(app.staticTexts["home.count.recommend"].label, "推荐：2")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：1")
        XCTAssertEqual(app.staticTexts["home.count.categoryAll"].label, "完整分类（辅助）：3")
    }

    /// AT-HOME-02-03: both empty inputs show no section skeletons while the
    /// H0 empty evidence (counts, auxiliary, retry) stays observable.
    /// One launch per test method (CHANGE-04 precedent): a two-launch loop
    /// exceeded CI's 60s per-test allowance on a cold simulator.
    @MainActor private func assertEmptyInputShowsNoSections(
        _ app: XCUIApplication, mode: String, auxiliary: String
    ) {
        app.launchArguments += ["--ui-home-fixture", mode]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 10))
        for section in Self.orderedSections {
            XCTAssertFalse(
                app.staticTexts["home.section.\(section.key).title"].exists,
                "\(section.key) title must not appear for \(mode)")
            XCTAssertFalse(
                sectionContent(app, key: section.key).exists,
                "\(section.key) placeholder must not appear for \(mode)")
        }
        XCTAssertEqual(
            app.staticTexts["home.count.categoryAll"].label, "完整分类（辅助）：\(auxiliary)")
        XCTAssertTrue(app.buttons["home.retry"].exists)
    }

    @MainActor func testEmptyFixtureShowsNoSectionsAndKeepsEmptyEvidence() {
        assertEmptyInputShowsNoSections(XCUIApplication(), mode: "empty", auxiliary: "0")
    }

    @MainActor func testEmptyCategoryFixtureShowsNoSectionsAndKeepsEmptyEvidence() {
        assertEmptyInputShowsNoSections(XCUIApplication(), mode: "empty-category", auxiliary: "3")
    }

    /// AT-HOME-02-04 (retention across switches): within ONE launch, after
    /// reaching the auxiliary last row, two rounds of category/cart round
    /// trips keep the committed content and the scroll position. Position is
    /// asserted by frame equality — the recorded row must sit at exactly the
    /// same viewport position after every round trip, which holds whether or
    /// not the content fits a single screen.
    @MainActor func testScrollPositionAndContentRetainedAcrossTabRoundTrips() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "valid"]
        app.launch()
        let loaded = app.staticTexts["home.loaded"]
        XCTAssertTrue(loaded.exists || loaded.waitForExistence(timeout: 10))
        let lastRow = app.staticTexts["home.count.categoryAll"]
        let scrollFrame = app.scrollViews["home.scroll"].frame.intersection(app.frame)
        let top = scrollFrame.minY
        let bottom = min(scrollFrame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertFalse(scrollFrame.isNull)
        XCTAssertGreaterThan(scrollFrame.width, 0)
        XCTAssertGreaterThan(bottom, top)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = scrollFrame.minX + scrollFrame.width * 0.98
        let start = origin.withOffset(CGVector(dx: x, dy: top + (bottom - top) * 0.9))
        let end = origin.withOffset(CGVector(dx: x, dy: top + (bottom - top) * 0.1))
        var before = lastRow.frame.minY
        for index in 0..<3 {
            if lastRow.isHittable { break }
            start.press(
                forDuration: 0.01, thenDragTo: end, withVelocity: 10_000,
                thenHoldForDuration: 0)
            let after = lastRow.frame.minY
            print("retention vertical drag \(index + 1): rowY=\(before)→\(after)")
            if after >= before - 1 { break }
            before = after
        }
        XCTAssertTrue(lastRow.isHittable, "auxiliary last row must be reachable by scrolling")
        // The gesture waits for idle. Confirm two consecutive initial samples
        // are stable before fixing the reference; never wait for it on return.
        let referenceMinY = lastRow.frame.minY
        XCTAssertEqual(
            lastRow.frame.minY, referenceMinY, accuracy: 1, "initial row must be settled")
        let bannerLabelBefore = app.staticTexts["home.count.banner"].label

        for round in 1...2 {
            let category = app.tabBars.buttons["分类"]
            category.tap()
            XCTAssertTrue(category.isSelected)
            let home = app.tabBars.buttons["首页"]
            home.tap()
            XCTAssertTrue(home.isSelected)
            XCTAssertTrue(loaded.exists || loaded.waitForExistence(timeout: 5))
            let cart = app.tabBars.buttons["购物车"]
            cart.tap()
            XCTAssertTrue(cart.isSelected)
            home.tap()
            XCTAssertTrue(home.isSelected)
            XCTAssertTrue(loaded.exists || loaded.waitForExistence(timeout: 5))
            XCTAssertTrue(lastRow.isHittable, "last row must stay reachable after round \(round)")
            XCTAssertEqual(
                lastRow.frame.minY, referenceMinY, accuracy: 1,
                "scroll position must be retained after round \(round)")
            XCTAssertEqual(
                app.staticTexts["home.count.banner"].label, bannerLabelBefore,
                "committed content must be unchanged after round \(round)")
        }
    }

    /// PRD-019 migration of the old re-tap expectation (before/after
    /// assertion table in the HOME-02-R1 handoff): a real re-tap of the
    /// selected home tab now scrolls to the fixed top anchor AND refreshes
    /// once — retap-sequence serves A (goods 10), B (11), then C (12).
    @MainActor func testReTapScrollsToTopAndRefreshesWithNewSnapshot() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "retap-sequence"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["home.source"].label, "工程夹具（retap-sequence）")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        let bannerTitle = sectionContent(app, key: "banner")
        let lastRow = app.staticTexts["home.count.categoryAll"]
        // Reach the full page's auxiliary row, including at accessibility
        // sizes, then prove the re-tap starts from a non-zero content position.
        let atRestMinY = lastRow.frame.minY
        reachAuxiliaryRow(app, row: lastRow, maximumDrags: 10)
        XCTAssertTrue(lastRow.isHittable)
        XCTAssertLessThan(
            lastRow.frame.minY, atRestMinY - 20,
            "precondition: actually scrolled to a non-zero position")
        // Real re-tap #1: scrolls to the fixed top anchor (deterministic
        // scrollTo alignment, recorded as the reference) + exactly one new
        // read (B). The anchor is observable through the first section being
        // back on screen at the recorded top position.
        app.tabBars.buttons["首页"].tap()
        let goods = app.staticTexts["home.count.goods"]
        let bSeen = NSPredicate(format: "label CONTAINS %@", "全部商品：11")
        expectation(for: bSeen, evaluatedWith: goods)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(bannerTitle.isHittable, "the first section must be back on screen")
        let scrollToTopMinY = bannerTitle.frame.minY
        // Bound the anchor against the real scroll viewport. The precise
        // assertions remain visibility and the second re-tap landing on the
        // SAME position.
        XCTAssertGreaterThan(
            scrollToTopMinY, app.scrollViews["home.scroll"].frame.minY - 160,
            "re-tap must land near the resting (top) position")
        // Real re-tap #2 while ALREADY AT TOP (AT: 停在顶部再按→C): a re-tap
        // at the top also refreshes, and the position stays put.
        app.tabBars.buttons["首页"].tap()
        let cSeen = NSPredicate(format: "label CONTAINS %@", "全部商品：12")
        expectation(for: cSeen, evaluatedWith: goods)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(bannerTitle.isHittable)
        XCTAssertEqual(
            bannerTitle.frame.minY, scrollToTopMinY, accuracy: 6,
            "an at-top re-tap must keep the same fixed top-anchor position")
        keepFeedbackScreenshot(app, name: "PR13-repeat-top")
    }

    /// R-PR08-COVERAGE-01: the full AT-HOME-02-R1-04 chain restored within
    /// ONE launch — first read A → hanging refresh accepted → three real
    /// busy re-taps (single pending request, scroll-to-top each time) →
    /// leaving the page cancels the refresh → returning keeps A with no
    /// re-fire → a NEW explicit re-tap starts another refresh. This is the
    /// combined chain 9.8.6 asks for; the earlier CHANGE-04 split covered
    /// each half in isolation and is merged back here.
    @MainActor func testPendingRefreshFullChainInOneLaunch() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "retap-pending"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        let bannerTitle = sectionContent(app, key: "banner")
        let lastRow = app.staticTexts["home.count.categoryAll"]
        let atRestMinY = lastRow.frame.minY
        var scrolledMinY = atRestMinY
        // A short page can reach its bottom while the banner stays hittable.
        // Stop on measured displacement, not on whether that title can be tapped.
        for _ in 0..<3 {
            app.swipeUp(velocity: .fast)
            usleep(400_000)
            scrolledMinY = lastRow.frame.minY
            if scrolledMinY < atRestMinY - 20 { break }
        }
        XCTAssertLessThan(
            scrolledMinY, atRestMinY - 20,
            "precondition: actually scrolled to a non-zero position")
        // Re-tap #1 starts the (hanging) refresh.
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        // Busy re-taps #2–#4: no second request, content unchanged, and each
        // re-tap scrolls back to the top even while busy.
        for _ in 1...3 {
            app.tabBars.buttons["首页"].tap()
            usleep(400_000)
            XCTAssertTrue(
                app.staticTexts["home.refreshing"].exists,
                "refresh must still be the single pending one")
            XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        }
        XCTAssertTrue(bannerTitle.isHittable, "re-tap scrolls to top even while busy")
        XCTAssertGreaterThan(
            lastRow.frame.minY, scrolledMinY + 20,
            "busy re-taps must move content back toward the fixed top anchor")
        // Leaving the page mid-refresh cancels the request and closes the
        // indicator; returning keeps the old content with no re-fire.
        app.tabBars.buttons["分类"].tap()
        usleep(500_000)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["home.refreshing"].waitForExistence(timeout: 1.5))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        // A NEW explicit re-tap in the same launch is accepted again (the
        // pending service hangs, so the indicator reappears).
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.refreshing"].label, "正在刷新")
        let refreshing = XCTAttachment(screenshot: app.screenshot())
        refreshing.name = "HOME03-refreshing-retained-content"
        refreshing.lifetime = .keepAlways
        add(refreshing)
    }

    /// A failed refresh keeps the old content and shows the retryable hint;
    /// the hint's retry button submits the successful B snapshot.
    @MainActor func testReTapRefreshFailureKeepsOldContentAndRetrySucceeds() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "retap-failure"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refresh.failed"].waitForExistence(timeout: 10))
        XCTAssertEqual(
            app.staticTexts["home.count.goods"].label, "全部商品：10", "old content must stay")
        XCTAssertTrue(app.buttons["home.refresh.retry"].exists)
        XCTAssertTrue(app.buttons["home.refresh.retry"].isHittable)
        XCTAssertEqual(app.staticTexts["home.refresh.failed"].label, "刷新失败，请重试")
        let failure = XCTAttachment(screenshot: app.screenshot())
        failure.name = "HOME03-refresh-failure-retained-content"
        failure.lifetime = .keepAlways
        add(failure)
        app.buttons["home.refresh.retry"].tap()
        let bSeen = NSPredicate(format: "label CONTAINS %@", "全部商品：11")
        expectation(for: bSeen, evaluatedWith: app.staticTexts["home.count.goods"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.staticTexts["home.refresh.failed"].exists)
    }
}

extension HomeLoadTests {
    @MainActor private func imageElement(_ app: XCUIApplication, _ state: String) -> XCUIElement {
        switch state {
        case "success", "failure", "missing", "placeholder":
            // The actionable banner is a Button; decorative product images
            // are Other elements and may carry the adapter's same state IDs.
            return app.buttons["home.image.\(state)"].firstMatch
        default:
            return app.descendants(matching: .any)["home.image.\(state)"].firstMatch
        }
    }

    @MainActor private func imageMetrics(_ app: XCUIApplication, _ expected: String) {
        let metrics = app.staticTexts["home.image.metrics"]
        let predicate = NSPredicate(format: "label == %@", expected)
        expectation(for: predicate, evaluatedWith: metrics)
        waitForExpectations(timeout: 8)
        XCTAssertEqual(metrics.label, expected)
    }

    @MainActor func testImageSuccessAndTabReturnUseOneCachedRequest() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "image-success"]
        app.launch()
        let loaded = app.staticTexts["home.loaded"]
        XCTAssertTrue(loaded.exists || loaded.waitForExistence(timeout: 10))
        let success = app.buttons["home.image.success"].firstMatch
        XCTAssertTrue(success.exists || success.waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        let frame = success.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.02)
        keepFeedbackScreenshot(app, name: "IMAGE01-success")
        app.tabBars.buttons["分类"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(loaded.exists || loaded.waitForExistence(timeout: 8))
        XCTAssertTrue(success.exists || success.waitForExistence(timeout: 8))
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：6")
    }

    @MainActor func testImageFailureKeepsHomeAndExplicitRefreshChangesURL() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "image-failure"]
        app.launch()
        XCTAssertTrue(imageElement(app, "failure").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        XCTAssertTrue(app.staticTexts["home.loaded"].exists)
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：6")
        keepFeedbackScreenshot(app, name: "IMAGE01-failure")
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：2；取消：0；首页读取：2")
        XCTAssertFalse(imageElement(app, "failure").exists)
    }

    @MainActor func testImagePendingLeaveCancelsAndReturnRestoresWithoutHomeReload() {
        // CI completed this unchanged full chain in ~90s; its only failure
        // was the default 60s cutoff. Use the existing Test Plan maximum.
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "image-pending"]
        app.launch()
        XCTAssertTrue(imageElement(app, "loading").waitForExistence(timeout: 10))
        // The fixture confirms an actual 11-second pending interval. On a slow
        // runner this may already be true when the first AX query returns.
        XCTAssertTrue(app.staticTexts["home.image.pending-aged"].waitForExistence(timeout: 15))
        XCTAssertTrue(imageElement(app, "loading").exists)
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        keepFeedbackScreenshot(app, name: "IMAGE01-loading")
        app.tabBars.buttons["分类"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(imageElement(app, "loading").waitForExistence(timeout: 8))
        imageMetrics(app, "图片请求：2；取消：1；首页读取：1")
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：3；取消：2；首页读取：2")
        XCTAssertFalse(imageElement(app, "loading").exists)
        app.buttons["home.image.release-old"].tap()
        let late = NSPredicate(format: "label == %@", "超时：0；旧响应：2")
        expectation(for: late, evaluatedWith: app.staticTexts["home.image.endings"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(imageElement(app, "success").exists)
        XCTAssertFalse(imageElement(app, "loading").exists)
        imageMetrics(app, "图片请求：3；取消：2；首页读取：2")
        keepFeedbackScreenshot(app, name: "IMAGE01-pink-B-after-late-blue-A")
    }

    @MainActor func testImageControlledTimeoutIsFailureNotCancellation() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "image-pending"]
        app.launch()
        XCTAssertTrue(imageElement(app, "loading").waitForExistence(timeout: 10))
        app.buttons["home.image.timeout"].tap()
        XCTAssertTrue(imageElement(app, "failure").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        XCTAssertEqual(app.staticTexts["home.image.endings"].label, "超时：1；旧响应：0")
        XCTAssertTrue(app.staticTexts["home.loaded"].exists)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：2；取消：0；首页读取：2")
    }

    @MainActor func testImageFastScrollKeepsOneRequestAndHomeSnapshot() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "image-success"]
        app.launch()
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        for _ in 0..<5 {
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(imageElement(app, "success").exists)
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：6")
    }
}

extension HomeLoadTests {
    @MainActor func testImageMissingAfterExplicitRefreshKeepsHome() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "image-success"]
        app.launch()
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        app.tabBars.buttons["首页"].tap()
        imageMetrics(app, "图片请求：2；取消：0；首页读取：2")
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(imageElement(app, "missing").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：2；取消：0；首页读取：3")
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：6")
        keepFeedbackScreenshot(app, name: "IMAGE01-missing")
    }
}

extension HomeLoadTests {
    @MainActor private func bannerApp(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", mode]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func bannerPage(_ app: XCUIApplication, _ index: Int, count: Int = 3) {
        let page = app.staticTexts["home.banner.page"]
        let expected = "第\(index)张，共\(count)张"
        expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: page)
        waitForExpectations(timeout: 8)
        XCTAssertEqual(page.label, expected)
    }

    /// Keep the entire image AND controls in the viewport for visual evidence.
    /// Vertical drags start beside the horizontal pager to avoid stealing its gesture.
    @MainActor private func revealBanner(_ app: XCUIApplication) {
        let next = app.buttons["home.banner.next"]
        for _ in 0..<4 {
            if next.isHittable && next.frame.maxY < app.tabBars.firstMatch.frame.minY { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.42))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(next.isHittable)
    }

    @MainActor func testBannerSingleHidesControlsAndUpdatesSameIDURL() {
        let app = bannerApp("banner-single")
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["home.banner.page"].exists)
        XCTAssertFalse(app.buttons["home.banner.previous"].exists)
        XCTAssertFalse(app.buttons["home.banner.next"].exists)
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        let before = imageElement(app, "success").screenshot()
        keepFeedbackScreenshot(app, name: "HOME04-single-A")
        app.tabBars.buttons["首页"].tap()
        imageMetrics(app, "图片请求：2；取消：0；首页读取：2")
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        XCTAssertNotEqual(
            before.pngRepresentation, imageElement(app, "success").screenshot().pngRepresentation)
        XCTAssertFalse(app.buttons["home.banner.next"].exists)
        keepFeedbackScreenshot(app, name: "HOME04-single-same-ID-new-image")
    }

    @MainActor func testBannerManualPagingBoundariesFailureAndMissing() {
        continueAfterFailure = false
        let app = bannerApp("banner-multiple")
        func observeImageState(_ state: String) -> Bool {
            let began = Date()
            let element = imageElement(app, state)
            let present = element.exists
            print(
                "banner image \(state): first exists=\(present), elapsed=\(Date().timeIntervalSince(began))"
            )
            if !present {
                // Diagnose a role mismatch once; an Any match never substitutes
                // for the original state locator's success requirement.
                let sameID = app.descendants(matching: .any)["home.image.\(state)"].firstMatch
                if sameID.exists {
                    print("banner image \(state): same-ID role=\(sameID.elementType.rawValue)")
                } else {
                    print("banner image \(state): same-ID absent")
                }
                // Include the first read and diagnostic lookup in the original
                // ten-second observation budget. An AX getter can itself block.
                let remaining = max(0, 10 - Date().timeIntervalSince(began))
                guard remaining > 0 else {
                    XCTFail("home.image.\(state) absent after first observation budget")
                    return false
                }
                let observed = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in element.exists }, object: nil)
                let result = XCTWaiter.wait(for: [observed], timeout: remaining)
                print(
                    "banner image \(state): wait=\(result.rawValue), elapsed=\(Date().timeIntervalSince(began))"
                )
                guard result == .completed else {
                    XCTFail("home.image.\(state) did not appear within its observation budget")
                    return false
                }
            }
            print("banner image \(state): observed role=\(element.elementType.rawValue)")
            return true
        }
        func requireMetrics(_ expected: String) -> Bool {
            let metrics = app.staticTexts["home.image.metrics"]
            // Read the live label first: the CI screenshot already showed the
            // expected counts before the old KVC predicate timed out.
            if metrics.label != expected {
                let observed = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in metrics.label == expected }, object: nil)
                guard XCTWaiter.wait(for: [observed], timeout: 8) == .completed else {
                    XCTFail("Expected \(expected); actual \(metrics.label)")
                    return false
                }
            }
            let actual = metrics.label
            XCTAssertEqual(actual, expected)
            return actual == expected
        }
        revealBanner(app)
        bannerPage(app, 1)
        XCTAssertFalse(app.buttons["home.banner.previous"].isEnabled)
        guard observeImageState("success") else { return }
        keepFeedbackScreenshot(app, name: "HOME04-success-complete")
        app.buttons["home.banner.next"].tap()
        bannerPage(app, 2)
        guard observeImageState("failure") else { return }
        guard requireMetrics("图片请求：2；取消：0；首页读取：1") else { return }
        keepFeedbackScreenshot(app, name: "HOME04-failure-complete")
        app.buttons["home.banner.next"].tap()
        bannerPage(app, 3)
        XCTAssertFalse(app.buttons["home.banner.next"].isEnabled)
        XCTAssertTrue(imageElement(app, "missing").exists)
        keepFeedbackScreenshot(app, name: "HOME04-missing-complete")
        app.buttons["home.banner.previous"].tap()
        bannerPage(app, 2)
        guard observeImageState("failure") else { return }
        // A failed image is not automatically retried by metrics/body changes.
        guard requireMetrics("图片请求：3；取消：0；首页读取：1") else { return }
        let pager = imageElement(app, "failure")
        pager.swipeRight()
        bannerPage(app, 1)
        guard observeImageState("success") else { return }
        imageElement(app, "success").swipeLeft()
        bannerPage(app, 2)
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：3")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        let last = app.staticTexts["home.count.categoryAll"]
        let scrollFrame = app.scrollViews["home.scroll"].frame.intersection(app.frame)
        let top = scrollFrame.minY
        let bottom = min(scrollFrame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertFalse(scrollFrame.isNull)
        XCTAssertGreaterThan(scrollFrame.width, 0)
        XCTAssertGreaterThan(bottom, top)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = scrollFrame.minX + scrollFrame.width * 0.98
        let start = origin.withOffset(CGVector(dx: x, dy: top + (bottom - top) * 0.9))
        let end = origin.withOffset(
            CGVector(dx: x, dy: top + (bottom - top) * 0.1))
        // Exercise a real vertical gesture beside the pager, even if the
        // auxiliary row is already visible. Stop if the content cannot move.
        var before = last.frame.minY
        for index in 0..<3 {
            start.press(
                forDuration: 0.01, thenDragTo: end, withVelocity: 10_000,
                thenHoldForDuration: 0)
            let after = last.frame.minY
            print("HOME04 vertical drag \(index + 1): rowY=\(before)→\(after)")
            if last.isHittable || after >= before - 1 { break }
            before = after
        }
        XCTAssertTrue(last.isHittable)
    }

    @MainActor func testBannerReconciliationInOneRefreshSequence() {
        let app = bannerApp("banner-reconcile")
        revealBanner(app)
        app.buttons["home.banner.next"].tap()
        bannerPage(app, 2)
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        app.tabBars.buttons["首页"].tap()
        imageMetrics(app, "图片请求：2；取消：0；首页读取：2")
        bannerPage(app, 2)
        XCTAssertTrue(app.descendants(matching: .any)["home.banner.current.910002"].exists)
        app.tabBars.buttons["首页"].tap()
        imageMetrics(app, "图片请求：3；取消：0；首页读取：3")
        bannerPage(app, 1, count: 2)
        XCTAssertTrue(app.descendants(matching: .any)["home.banner.current.910003"].exists)
        app.tabBars.buttons["首页"].tap()
        imageMetrics(app, "图片请求：3；取消：0；首页读取：4")
        XCTAssertFalse(app.staticTexts["home.section.banner.title"].exists)
        XCTAssertFalse(app.buttons["home.banner.next"].exists)
        app.tabBars.buttons["首页"].tap()
        imageMetrics(app, "图片请求：3；取消：0；首页读取：5")
        XCTAssertFalse(app.staticTexts["home.section.banner.title"].exists)
        XCTAssertFalse(app.staticTexts["home.banner.page"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.banner.current.910001"].exists)
    }

    @MainActor func testBannerRefreshFailurePreservesSelectedPageAndRetry() {
        let app = bannerApp("banner-refresh-failure")
        revealBanner(app)
        app.buttons["home.banner.next"].tap()
        bannerPage(app, 2)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refresh.failed"].waitForExistence(timeout: 10))
        bannerPage(app, 2)
        imageMetrics(app, "图片请求：2；取消：0；首页读取：2")
        XCTAssertEqual(app.staticTexts["home.count.banner"].label, "轮播：3")
        app.buttons["home.refresh.retry"].tap()
        imageMetrics(app, "图片请求：2；取消：0；首页读取：3")
        bannerPage(app, 2)
        XCTAssertFalse(app.staticTexts["home.refresh.failed"].exists)
    }

    @MainActor func testBannerPendingPageCancellationAndTabRetention() {
        continueAfterFailure = false
        let app = bannerApp("banner-pending")
        func observeImageState(_ state: String) -> Bool {
            let began = Date()
            let element = imageElement(app, state)
            let present = element.exists
            print(
                "banner image \(state): first exists=\(present), elapsed=\(Date().timeIntervalSince(began))"
            )
            if !present {
                // Diagnose a role mismatch once; an Any match never substitutes
                // for the original state locator's success requirement.
                let sameID = app.descendants(matching: .any)["home.image.\(state)"].firstMatch
                if sameID.exists {
                    print("banner image \(state): same-ID role=\(sameID.elementType.rawValue)")
                } else {
                    print("banner image \(state): same-ID absent")
                }
                // Include the first read and diagnostic lookup in the original
                // ten-second observation budget. An AX getter can itself block.
                let remaining = max(0, 10 - Date().timeIntervalSince(began))
                guard remaining > 0 else {
                    XCTFail("home.image.\(state) absent after first observation budget")
                    return false
                }
                let observed = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in element.exists }, object: nil)
                let result = XCTWaiter.wait(for: [observed], timeout: remaining)
                print(
                    "banner image \(state): wait=\(result.rawValue), elapsed=\(Date().timeIntervalSince(began))"
                )
                guard result == .completed else {
                    XCTFail("home.image.\(state) did not appear within its observation budget")
                    return false
                }
            }
            print("banner image \(state): observed role=\(element.elementType.rawValue)")
            return true
        }
        revealBanner(app)
        guard observeImageState("loading") else { return }
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        keepFeedbackScreenshot(app, name: "HOME04-loading-complete")
        app.buttons["home.banner.next"].tap()
        bannerPage(app, 2)
        guard observeImageState("success") else { return }
        imageMetrics(app, "图片请求：2；取消：1；首页读取：1")
        XCTAssertFalse(imageElement(app, "loading").exists)
        keepFeedbackScreenshot(app, name: "HOME04-B-after-late-A")
        app.buttons["home.banner.previous"].tap()
        bannerPage(app, 1)
        guard observeImageState("loading") else { return }
        app.tabBars.buttons["分类"].tap()
        app.tabBars.buttons["首页"].tap()
        bannerPage(app, 1)
        imageMetrics(app, "图片请求：4；取消：2；首页读取：1")
    }

    /// Non-first selection and the exact bottom viewport survive ordinary
    /// tab changes together; no home re-tap or implicit read is involved.
    @MainActor func testSelectedBannerAndBottomPositionRetainedAcrossTabs() {
        let app = bannerApp("banner-pending")
        revealBanner(app)
        app.buttons["home.banner.next"].tap()
        bannerPage(app, 2)
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：2；取消：1；首页读取：1")
        let lastRow = app.staticTexts["home.count.categoryAll"]
        reachAuxiliaryRow(app, row: lastRow, maximumDrags: 8)
        XCTAssertTrue(lastRow.isHittable, "the auxiliary last row must be reached")
        let referenceMinY = lastRow.frame.minY
        for round in 1...2 {
            for tab in ["分类", "购物车"] {
                app.tabBars.buttons[tab].tap()
                app.tabBars.buttons["首页"].tap()
                XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
                XCTAssertTrue(
                    lastRow.isHittable, "bottom row must stay visible after \(tab), round \(round)")
                XCTAssertEqual(lastRow.frame.minY, referenceMinY, accuracy: 1)
            }
            bannerPage(app, 2)
            imageMetrics(app, "图片请求：2；取消：1；首页读取：1")
        }
        keepFeedbackScreenshot(app, name: "PR13-selected-bottom-retained")
    }

    @MainActor func testBannerFastPageRoundTripsAreBounded() {
        let app = bannerApp("banner-pending")
        revealBanner(app)
        // The final totals include the initial A subscription, not just page selection.
        print("Initial banner sources: \(app.staticTexts["home.image.urlMetrics"].label)")
        XCTAssertTrue(imageElement(app, "loading").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        for _ in 0..<5 {
            app.buttons["home.banner.next"].tap()
            app.buttons["home.banner.previous"].tap()
        }
        bannerPage(app, 1)
        XCTAssertTrue(imageElement(app, "loading").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：7；取消：5；首页读取：1")
        XCTAssertTrue(
            app.staticTexts["home.image.urlMetrics"].label.contains("/banner-pending-a=6/5"))
        XCTAssertTrue(
            app.staticTexts["home.image.urlMetrics"].label.contains("/banner-success-b=1/0"))
        XCTAssertTrue(app.staticTexts["home.image.urlMetrics"].label.contains("迟到尝试：5"))
    }
}

extension HomeLoadTests {
    @MainActor func testBannerSelectedPageSurvivesBusyRetapsAndCancelledRefresh() {
        continueAfterFailure = false
        let app = bannerApp("banner-pending")
        let aged = app.staticTexts["home.image.pending-aged"]
        let began = Date()
        if !aged.exists {
            let remaining = max(0, 10 - Date().timeIntervalSince(began))
            let settledHUD = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in aged.exists }, object: nil)
            guard remaining > 0,
                XCTWaiter.wait(for: [settledHUD], timeout: remaining) == .completed
            else {
                XCTFail("pending-age HUD did not settle within its 10-second precondition")
                return
            }
        }
        print("busy HUD aged after \(Date().timeIntervalSince(began)) seconds")
        func requirePage2() -> Bool {
            let page = app.staticTexts["home.banner.page"]
            let expected = "第2张，共3张"
            let began = Date()
            var actual = page.label
            if actual != expected {
                let remaining = max(0, 8 - Date().timeIntervalSince(began))
                let selected = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in
                        let value = page.label
                        if value != actual { print("busy page \(actual)→\(value)") }
                        actual = value
                        return value == expected
                    }, object: nil)
                guard remaining > 0,
                    XCTWaiter.wait(for: [selected], timeout: remaining) == .completed
                else {
                    keepFeedbackScreenshot(app, name: "busy-page-precondition-failure")
                    XCTFail("Expected \(expected); actual \(actual)")
                    return false
                }
            }
            let finalActual = page.label
            XCTAssertEqual(finalActual, expected)
            return finalActual == expected
        }
        revealBanner(app)
        // The age marker inserts a DEBUG HUD row. Resolve the button only
        // after that known layout transition; keep one original native tap.
        let next = app.buttons["home.banner.next"]
        let frame = next.frame
        let scroll = app.scrollViews["home.scroll"].frame.intersection(app.frame)
        let top = scroll.minY
        let bottom = min(scroll.maxY, app.tabBars.firstMatch.frame.minY)
        let viewport = CGRect(x: scroll.minX, y: top, width: scroll.width, height: bottom - top)
        XCTAssertEqual(app.staticTexts["home.banner.page"].label, "第1张，共3张")
        XCTAssertEqual(
            app.staticTexts["home.image.metrics"].label, "图片请求：1；取消：0；首页读取：1")
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertTrue(
            viewport.contains(frame), "next button must be completely inside the viewport")
        XCTAssertEqual(next.frame.minY, frame.minY, accuracy: 1, "initial button must be settled")
        print("busy settled next=\(frame), viewport=\(viewport)")
        next.tap()
        guard requirePage2() else { return }
        let success = imageElement(app, "success")
        XCTAssertTrue(success.exists || success.waitForExistence(timeout: 10))
        app.tabBars.buttons["首页"].tap()
        let refreshing = app.staticTexts["home.refreshing"]
        XCTAssertTrue(refreshing.exists || refreshing.waitForExistence(timeout: 10))
        for _ in 0..<3 { app.tabBars.buttons["首页"].tap() }
        imageMetrics(app, "图片请求：2；取消：1；首页读取：2")
        guard requirePage2() else { return }
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        app.tabBars.buttons["分类"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertFalse(app.staticTexts["home.refreshing"].waitForExistence(timeout: 1.5))
        imageMetrics(app, "图片请求：2；取消：1；首页读取：2")
        guard requirePage2() else { return }
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(refreshing.exists || refreshing.waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：2；取消：1；首页读取：3")
        guard requirePage2() else { return }
    }
}

extension HomeLoadTests {
    @MainActor private func pullHome(_ app: XCUIApplication, fast: Bool = false) {
        let scroll = app.scrollViews["home.scroll"]
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        if fast {
            start.press(
                forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        } else {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    @MainActor func testPullRefreshSuccessReplacesSnapshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "retap-sequence"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        pullHome(app)
        let goods = app.staticTexts["home.count.goods"]
        expectation(for: NSPredicate(format: "label == %@", "全部商品：11"), evaluatedWith: goods)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(goods.label, "全部商品：11")
        XCTAssertFalse(app.staticTexts["home.refreshing"].exists)
        // A second distinct short pull must be accepted exactly once too.
        pullHome(app, fast: true)
        expectation(for: NSPredicate(format: "label == %@", "全部商品：12"), evaluatedWith: goods)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(goods.label, "全部商品：12")
        XCTAssertFalse(app.staticTexts["home.refreshing"].exists)
    }

    @MainActor func testPullRefreshFailureKeepsContentAndRetryRecovers() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "retap-failure"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        pullHome(app)
        XCTAssertTrue(app.staticTexts["home.refresh.failed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        XCTAssertFalse(app.staticTexts["home.refreshing"].exists)
        app.buttons["home.refresh.retry"].tap()
        let goods = app.staticTexts["home.count.goods"]
        expectation(for: NSPredicate(format: "label == %@", "全部商品：11"), evaluatedWith: goods)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["home.refresh.failed"].exists)
    }

    @MainActor func testBusyPullDoesNotQueueAndLeaveCancelsAcceptedRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "page-controlled"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 5))
        pullHome(app)  // Busy pull is rejected; never queues or restarts the read.
        XCTAssertEqual(app.staticTexts["home.page.requests"].label, "读取：2；取消：0")
        app.tabBars.buttons["分类"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.page.requests"].label, "读取：2；取消：1")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        XCTAssertFalse(app.staticTexts["home.refreshing"].exists)
        XCTAssertFalse(app.staticTexts["home.refresh.failed"].exists)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.page.requests"].label, "读取：3；取消：1")
        app.buttons["home.page.success"].tap()
        XCTAssertFalse(app.staticTexts["home.refreshing"].exists)
    }
}

extension HomeLoadTests {
    @MainActor func testR2ProductSectionsKeepDistinctIdentitiesAndYuanPrices() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "valid"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        for (key, id, price) in [
            ("flashSale", "830001", "3,999.00"), ("recommend", "830009", "4,999.00"),
            ("goods", "1", "5,499.00"),
        ] {
            revealSectionContent(app, key: key)
            XCTAssertTrue(app.staticTexts["home.\(key).\(id).title"].exists)
            XCTAssertTrue(app.staticTexts["home.\(key).\(id).price"].label.contains(price))
        }
        app.buttons["home.search"].tap()
        XCTAssertTrue(app.staticTexts["home.unavailable"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["home.loaded"].exists)
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
    }
}

extension HomeLoadTests {
    @MainActor func testBannerUnavailableActionShowsAppFeedbackWithoutReadingAgain() {
        let app = bannerApp("banner-multiple")
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        app.buttons["home.banner.current.910001"].tap()
        XCTAssertTrue(app.staticTexts["home.unavailable"].waitForExistence(timeout: 2))
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        bannerPage(app, 1)
    }
}

extension HomeLoadTests {
    @MainActor private func assertApprovedHomeDisplay(accessibility: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "valid"]
        if accessibility {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        for key in ["banner", "coupon", "category"] {
            XCTAssertFalse(app.staticTexts["home.section.\(key).title"].exists)
        }
        func reveal(_ element: XCUIElement) {
            let scroll = app.scrollViews["home.scroll"]
            for _ in 0..<8 {
                if element.exists, element.isHittable { return }
                let frame = scroll.frame
                let bottom = min(frame.maxY, app.tabBars.firstMatch.frame.minY) - 12
                scroll.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frame.width / 2, dy: bottom - frame.minY))
                    .press(
                        forDuration: 0.05,
                        thenDragTo: scroll.coordinate(withNormalizedOffset: .zero)
                            .withOffset(CGVector(dx: frame.width / 2, dy: 40)))
            }
            XCTAssertTrue(element.isHittable)
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "home-display-\(accessibility ? "AX" : "normal")-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let coupon = app.staticTexts["home.coupon.860001.title"]
        reveal(coupon)
        let claim = app.staticTexts["home.coupon.860001.claim"]
        XCTAssertTrue(claim.isHittable)
        XCTAssertLessThan(coupon.frame.maxX, claim.frame.minX)
        XCTAssertTrue(coupon.frame.minY < claim.frame.maxY && claim.frame.minY < coupon.frame.maxY)
        XCTAssertFalse(coupon.label.isEmpty)
        capture("coupon")
        if !accessibility {
            reveal(app.staticTexts["home.flashSale.830001.title"])
            XCTAssertFalse(app.staticTexts["home.flashSale.830001.sold"].exists)
            capture("featured")
        }
        let rows =
            accessibility
            ? [
                ("recommend", "830009", "2101"), ("recommend", "830010", "4683"),
                ("goods", "1", "459"),
            ]
            : [("recommend", "830009", "2101"), ("goods", "1", "459")]
        for (key, id, sold) in rows {
            let price = app.staticTexts["home.\(key).\(id).price"]
            let count = app.staticTexts["home.\(key).\(id).sold"]
            reveal(count)
            if accessibility, id == "830010" {
                let scroll = app.scrollViews["home.scroll"]
                let frame = scroll.frame
                let bottom = min(frame.maxY, app.tabBars.firstMatch.frame.minY) - 24
                let excess = max(price.frame.maxY, count.frame.maxY) - bottom
                if excess > 0 {
                    let start = CGPoint(x: frame.width / 2, y: bottom - frame.minY)
                    let distance = min(excess + 24, start.y - 40)
                    scroll.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: start.x, dy: start.y))
                        .press(
                            forDuration: 0.05,
                            thenDragTo: scroll.coordinate(withNormalizedOffset: .zero)
                                .withOffset(CGVector(dx: start.x, dy: start.y - distance)))
                }
                XCTAssertLessThanOrEqual(max(price.frame.maxY, count.frame.maxY), bottom)
            }
            XCTAssertTrue(price.isHittable)
            XCTAssertEqual(count.label, "已售\(sold)件")
            print("Home display \(key) amount frame=\(price.frame), sold frame=\(count.frame)")
            XCTAssertLessThanOrEqual(price.frame.maxX, count.frame.minX)
            XCTAssertTrue(
                price.frame.minY < count.frame.maxY && count.frame.minY < price.frame.maxY,
                "price and actual sold count must share one row")
            capture(id == "830010" ? "recommend-4683" : key)
        }
    }
    @MainActor func testApprovedHomeDisplayAtNormalSize() {
        assertApprovedHomeDisplay(accessibility: false)
    }
    @MainActor func testApprovedHomeDisplayAtAccessibilitySize() {
        assertApprovedHomeDisplay(accessibility: true)
    }
}
