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
    /// Layout/order evidence runs under the controlled manual banner gate:
    /// autoplay is not the behavior under test here. LazyVGrid rows (the
    /// category cells) can leave the AX tree when far offscreen, so the
    /// vertical order is proven by a top→bottom discovery walk — frames are
    /// only compared among anchors co-present at one scroll position — while
    /// the horizontal insets are scroll-stable and read from any capture.
    @MainActor func testValidFixtureShowsSixSectionsInPRDOrder() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "valid", "--ui-banner-manual"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.source"].label, "工程夹具（valid）")
        // All six sections retain real content; only product headings remain.
        for section in Self.orderedSections {
            XCTAssertEqual(
                app.staticTexts["home.section.\(section.key).title"].exists,
                !["banner", "coupon", "category"].contains(section.key),
                "only product section headings remain")
        }
        XCTAssertTrue(
            currentBanner(app).exists, "banner must show its real selected image for valid input")
        var discoveryOrder: [String] = []
        var capturedMinX: [String: CGFloat] = [:]
        for _ in 0..<24 where discoveryOrder.count < Self.orderedSections.count {
            var present: [(key: String, minY: CGFloat)] = []
            for section in Self.orderedSections {
                // Product sections anchor on their headings (the approved
                // 16/16+12 insets); the headingless top three on content.
                let anchor =
                    ["banner", "coupon", "category"].contains(section.key)
                    ? sectionContent(app, key: section.key)
                    : app.staticTexts["home.section.\(section.key).title"]
                if anchor.exists {
                    let frame = anchor.frame
                    if capturedMinX[section.key] == nil {
                        present.append((section.key, frame.minY))
                    }
                    capturedMinX[section.key] = frame.minX
                }
            }
            discoveryOrder.append(
                contentsOf: present.sorted { $0.minY < $1.minY }.map(\.key))
            if discoveryOrder.count < Self.orderedSections.count {
                app.swipeUp(velocity: .slow)
                usleep(400_000)
            }
        }
        XCTAssertEqual(
            discoveryOrder, Self.orderedSections.map(\.key),
            "sections must be discovered in PRD-015 vertical order")
        XCTAssertEqual(capturedMinX.count, Self.orderedSections.count, "all anchors captured")
        // Featured adds its approved 12pt inner inset to the shared 16pt outer margin.
        let leading = app.scrollViews["home.scroll"].frame.minX + 16
        for (index, section) in Self.orderedSections.enumerated() where index >= 3 {
            let innerInset: CGFloat = index == 3 ? 12 : 0
            XCTAssertEqual(
                capturedMinX[section.key] ?? -1, leading + innerInset, accuracy: 2,
                "\(section.key) title must respect its approved inset")
        }
        // Read through the whole content: the auxiliary last row is reachable.
        let lastRow = app.staticTexts["home.count.categoryAll"]
        for _ in 0..<10 {
            if lastRow.exists, lastRow.isHittable { break }
            app.swipeUp(velocity: .slow)
            usleep(400_000)
        }
        XCTAssertTrue(lastRow.isHittable, "auxiliary last row must be reachable")
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
    /// busy re-taps (HOME-RETAP-LATEST: each starts the latest request and
    /// supersedes the hanging one; content stays A throughout; scroll-to-top
    /// each time) → leaving the page cancels the latest refresh → returning
    /// keeps A with no re-fire → a NEW explicit re-tap starts another
    /// refresh. This is the combined chain 9.8.6 asks for; the earlier
    /// CHANGE-04 split covered each half in isolation and is merged back.
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
        app.launchArguments += ["--ui-home-fixture", "image-success", "--ui-banner-manual"]
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
        app.launchArguments += ["--ui-home-fixture", "image-failure", "--ui-banner-manual"]
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
        app.launchArguments += ["--ui-home-fixture", "image-pending", "--ui-banner-manual"]
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
        app.launchArguments += ["--ui-home-fixture", "image-pending", "--ui-banner-manual"]
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
        app.launchArguments += ["--ui-home-fixture", "image-success", "--ui-banner-manual"]
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
        app.launchArguments += ["--ui-home-fixture", "image-success", "--ui-banner-manual"]
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
    /// Image/business chains default to the controlled manual gate so their
    /// exact request/cancel counts cannot be disturbed by real autoplay;
    /// `automatic: true` deliberately launches WITHOUT the gate.
    @MainActor private func bannerApp(_ mode: String, automatic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", mode]
        if !automatic { app.launchArguments += ["--ui-banner-manual"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func currentBanner(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home.banner.current.")
        ).firstMatch
    }

    @MainActor private func bannerIndicators(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["home.banner.indicators"].firstMatch
    }

    @MainActor private func bannerPage(_ app: XCUIApplication, _ index: Int, count: Int = 3) {
        let page = currentBanner(app)
        let expected = "第\(index)张，共\(count)张"
        if page.value as? String != expected {
            let observed = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in page.value as? String == expected }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 8), .completed)
        }
        XCTAssertEqual(page.value as? String, expected)
        let indicators = bannerIndicators(app)
        XCTAssertEqual(indicators.exists, count > 1)
        if count > 1 {
            XCTAssertEqual(indicators.value as? String, "第\(index)页，共\(count)页")
        }
    }

    /// The current leaf fills the real image; keep the whole image inside the
    /// scroll viewport for visual evidence. Vertical drags start beside the
    /// horizontal pager to avoid stealing its gesture. A banner that is IN
    /// bounds but not yet hittable (a transient miss while the autoplay wrap
    /// animates or AX settles — the CI push-test failure) must be waited for,
    /// never scrolled away from; an out-of-bounds banner is recovered with a
    /// DIRECTIONAL drag instead of always scrolling up.
    /// A banner that is IN bounds but not yet hittable (a transient miss
    /// while the autoplay wrap animates or AX settles — the CI push failure)
    /// is waited for, never scrolled away from; a banner fully ABOVE the
    /// viewport is recovered with a directional drag. The original four
    /// attempts and the exact in-bounds geometry are unchanged.
    @MainActor private func revealBanner(_ app: XCUIApplication) {
        for _ in 0..<4 {
            let banner = currentBanner(app)
            let scroll = app.scrollViews["home.scroll"].frame.intersection(app.frame)
            let bottom = min(scroll.maxY, app.tabBars.firstMatch.frame.minY)
            if banner.exists {
                let frame = banner.frame
                if frame.minY >= scroll.minY, frame.maxY <= bottom {
                    if banner.isHittable { return }
                    let settled = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in banner.isHittable }, object: nil)
                    if XCTWaiter.wait(for: [settled], timeout: 3) == .completed { return }
                    continue
                }
                if frame.maxY < scroll.minY {
                    // Fully above the viewport: drag content back down.
                    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.42))
                    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.75))
                    start.press(forDuration: 0.01, thenDragTo: end)
                    continue
                }
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.42))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(currentBanner(app).isHittable)
    }

    @MainActor func testBannerSingleHidesControlsAndUpdatesSameIDURL() {
        let app = bannerApp("banner-single")
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["home.banner.page"].exists)
        XCTAssertFalse(app.buttons["home.banner.previous"].exists)
        XCTAssertFalse(app.buttons["home.banner.next"].exists)
        XCTAssertFalse(bannerIndicators(app).exists, "single banner has no pagination dots")
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        let before = imageElement(app, "success").screenshot()
        keepFeedbackScreenshot(app, name: "HOME04-single-A")
        app.tabBars.buttons["首页"].tap()
        imageMetrics(app, "图片请求：2；取消：0；首页读取：2")
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        XCTAssertNotEqual(
            before.pngRepresentation, imageElement(app, "success").screenshot().pngRepresentation)
        XCTAssertFalse(app.buttons["home.banner.next"].exists)
        XCTAssertFalse(bannerIndicators(app).exists, "same-ID single image still has no dots")
        keepFeedbackScreenshot(app, name: "HOME04-single-same-ID-new-image")
    }

    @MainActor func testBannerManualPagingBoundariesFailureAndMissing() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "banner-multiple", "--ui-banner-manual"]
        let launched = ProcessInfo.processInfo.systemUptime
        app.launch()
        print("HOME04 launch returned after \(ProcessInfo.processInfo.systemUptime - launched)s")
        let loaded = app.staticTexts["home.loaded"]
        XCTAssertTrue(loaded.exists || loaded.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["home.banner.page"].exists)
        XCTAssertFalse(app.buttons["home.banner.previous"].exists)
        XCTAssertFalse(app.buttons["home.banner.next"].exists)

        // A checkpoint reads one live AX hierarchy. Page, dots, image role and
        // request counts belong to that same observation, rather than each
        // attribute causing another remote query. Every swipe replaces it.
        var observation: [any XCUIElementSnapshot] = []
        func descendants(_ node: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            [node] + node.children.flatMap { descendants($0) }
        }
        func observe() throws {
            let began = ProcessInfo.processInfo.systemUptime
            observation = descendants(try app.snapshot())
            print("HOME04 checkpoint snapshot \(ProcessInfo.processInfo.systemUptime - began)s")
        }
        func requirePage(_ index: Int) throws {
            try observe()
            let expected = "第\(index)张，共3张"
            func observedPage() -> String? {
                observation.first { $0.identifier.hasPrefix("home.banner.current.") }?.value
                    as? String
            }
            if observedPage() != expected {
                let page = currentBanner(app)
                let settled = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in page.value as? String == expected },
                    object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed)
                try observe()
            }
            XCTAssertEqual(observedPage(), expected)
            let dots = observation.first { $0.identifier == "home.banner.indicators" }
            XCTAssertEqual(dots != nil, true)
            XCTAssertEqual(dots?.value as? String, "第\(index)页，共3页")
        }
        func observeImageState(_ state: String) throws {
            func present() -> Bool {
                observation.contains {
                    $0.identifier == "home.image.\(state)" && $0.elementType == .button
                }
            }
            if !present() {
                let element = imageElement(app, state)
                let settled = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in element.exists }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
                try observe()
            }
            XCTAssertTrue(present(), "the actionable image must expose \(state)")
        }
        func requireMetrics(_ expected: String) {
            var actual = observation.first { $0.identifier == "home.image.metrics" }?.label
            if actual != expected {
                let metrics = app.staticTexts["home.image.metrics"]
                let settled = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in
                        actual = metrics.label
                        return actual == expected
                    }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed)
            }
            XCTAssertEqual(actual, expected)
        }
        revealBanner(app)
        try requirePage(1)
        let appFrame = app.frame
        let bannerFrame = try XCTUnwrap(
            observation.first { $0.identifier.hasPrefix("home.banner.current.") }?.frame)
        let y = (bannerFrame.midY - appFrame.minY) / appFrame.height
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: y))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y))
        func swipeLeft() {
            right.press(
                forDuration: 0.01, thenDragTo: left, withVelocity: .fast, thenHoldForDuration: 0)
        }
        func swipeRight() {
            left.press(
                forDuration: 0.01, thenDragTo: right, withVelocity: .fast, thenHoldForDuration: 0)
        }
        // The same full gesture chain, including both outward boundary swipes.
        swipeRight()
        try requirePage(1)
        try observeImageState("success")
        keepFeedbackScreenshot(app, name: "HOME04-success-complete")
        swipeLeft()
        try requirePage(2)
        try observeImageState("failure")
        requireMetrics("图片请求：2；取消：0；首页读取：1")
        keepFeedbackScreenshot(app, name: "HOME04-failure-complete")
        swipeLeft()
        try requirePage(3)
        swipeLeft()
        try requirePage(3)
        XCTAssertTrue(
            observation.contains {
                $0.identifier == "home.image.missing" && $0.elementType == .button
            })
        keepFeedbackScreenshot(app, name: "HOME04-missing-complete")
        swipeRight()
        try requirePage(2)
        try observeImageState("failure")
        // A failed image is not automatically retried by observation changes.
        requireMetrics("图片请求：3；取消：0；首页读取：1")
        swipeRight()
        try requirePage(1)
        try observeImageState("success")
        swipeLeft()
        try requirePage(2)
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
        currentBanner(app).swipeLeft()
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
        XCTAssertFalse(currentBanner(app).exists)
        XCTAssertFalse(bannerIndicators(app).exists, "empty banner section has no pagination dots")
        app.tabBars.buttons["首页"].tap()
        imageMetrics(app, "图片请求：3；取消：0；首页读取：5")
        XCTAssertFalse(app.staticTexts["home.section.banner.title"].exists)
        XCTAssertFalse(app.staticTexts["home.banner.page"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.banner.current.910001"].exists)
        XCTAssertFalse(bannerIndicators(app).exists, "refilled single banner has no dots")
    }

    @MainActor func testBannerRefreshFailurePreservesSelectedPageAndRetry() {
        let app = bannerApp("banner-refresh-failure")
        revealBanner(app)
        currentBanner(app).swipeLeft()
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
        currentBanner(app).swipeLeft()
        bannerPage(app, 2)
        guard observeImageState("success") else { return }
        imageMetrics(app, "图片请求：2；取消：1；首页读取：1")
        XCTAssertFalse(imageElement(app, "loading").exists)
        keepFeedbackScreenshot(app, name: "HOME04-B-after-late-A")
        currentBanner(app).swipeRight()
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
        currentBanner(app).swipeLeft()
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
            currentBanner(app).swipeLeft()
            currentBanner(app).swipeRight()
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
    /// HOME-RETAP-DEBOUNCE (2026-10-20). Measured reality: an XCUITest
    /// coordinate tap costs ~2.3s on this stack (printed below), so real UI
    /// taps are SEPARATE quiet batches — this chain therefore proves the
    /// per-batch event wiring, real supersede cancellation, latest-commit,
    /// busy-pull rejection and recovery/leave contracts; the sub-300ms MERGE
    /// itself is proven by the controlled-time HomeViewModelTests matrix
    /// (taps at virtual 0/100/220ms → exactly one read), not faked here.
    @MainActor func testBannerSelectedPageSurvivesBusyRetapsAndCancelledRefresh() {
        continueAfterFailure = false
        // APPROVAL-AWAY-BUSY-120-20261019: the full controlled chain exceeds
        // the default allowance on slow runners.
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "page-controlled", "--ui-banner-manual"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        func requests(_ label: String, _ message: String) {
            XCTAssertEqual(app.staticTexts["home.page.requests"].label, label, message)
        }
        func batchTap(_ name: String) {
            let began = Date()
            app.tabBars.buttons["首页"].tap()
            print("RETAP-DEBOUNCE batch \(name) tap at \(began)")
        }
        revealBanner(app)
        // Select a non-first banner; its identity must survive everything.
        currentBanner(app).swipeLeft()
        bannerPage(app, 2, count: 6)
        // Each quiet re-tap batch starts exactly one read; the NEXT batch
        // supersedes the hanging read with a REAL owner-issued cancellation
        // counted once by the per-request controlled service.
        batchTap("1")
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        requests("读取：2；取消：0", "batch 1 (launch was read 1) starts one read")
        batchTap("2")
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        requests("读取：3；取消：1", "batch 2 really cancels the hanging read once")
        batchTap("3")
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        requests("读取：4；取消：2", "batch 3 supersedes in flight exactly once again")
        // A busy pull while the latest read hangs: rejected, nothing added.
        pullHome(app)
        requests("读取：4；取消：2", "busy pull neither queues nor cancels nor adds")
        bannerPage(app, 2, count: 6)
        // The latest request takes over: releasing it commits its snapshot.
        app.buttons["home.page.success"].tap()
        XCTAssertFalse(app.staticTexts["home.refreshing"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：11")
        bannerPage(app, 2, count: 6)
        // A failed LATEST batch keeps the committed content behind the hint;
        // the hint's OWN retry is immediate and its success replaces again.
        batchTap("4")
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        requests("读取：5；取消：2", "batch 4 starts one read")
        app.buttons["home.page.failure"].tap()
        XCTAssertTrue(app.staticTexts["home.refresh.failed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：11")
        app.buttons["home.refresh.retry"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        requests("读取：6；取消：2", "the hint retry is an immediate entry")
        app.buttons["home.page.success"].tap()
        XCTAssertFalse(app.staticTexts["home.refreshing"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：11")
        bannerPage(app, 2, count: 6)
        // Leaving mid-flight cancels the latest; returning keeps the
        // committed content and the selected banner without any re-fire.
        batchTap("5")
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        requests("读取：7；取消：2", "batch 5 starts request #7")
        app.tabBars.buttons["分类"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["home.refreshing"].waitForExistence(timeout: 1.5))
        requests("读取：7；取消：3", "leaving cancels the latest request exactly once")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：11")
        bannerPage(app, 2, count: 6)
        keepFeedbackScreenshot(app, name: "RETAP-DEBOUNCE-busy-selected-survives")
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

    /// A pull while a (debounced) refresh hangs is REJECTED — the original
    /// pull contract: nothing queues, nothing is cancelled or added. Leaving
    /// cancels the accepted request; returning keeps content without any
    /// re-fire; a later re-tap batch refreshes and succeeds.
    @MainActor func testBusyPullDoesNotQueueAndLeaveCancelsAcceptedRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "page-controlled", "--ui-banner-manual"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        func requests(_ label: String, _ message: String) {
            XCTAssertEqual(app.staticTexts["home.page.requests"].label, label, message)
        }
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 5))
        requests("读取：2；取消：0", "the re-tap batch starts request #2")
        // Busy pull: rejected; never queues or restarts the read.
        pullHome(app)
        requests("读取：2；取消：0", "busy pull adds nothing")
        app.tabBars.buttons["分类"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        requests("读取：2；取消：1", "leaving cancels the accepted request")
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        XCTAssertFalse(app.staticTexts["home.refreshing"].exists)
        XCTAssertFalse(app.staticTexts["home.refresh.failed"].exists)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 5))
        requests("读取：3；取消：1", "the later re-tap batch starts request #3")
        app.buttons["home.page.success"].tap()
        XCTAssertFalse(app.staticTexts["home.refreshing"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：11")
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
        XCTAssertTrue(app.staticTexts["home.loaded"].exists)
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
    }
}

extension HomeLoadTests {
    @MainActor func testBannerInitialImageKeepsSingleHomeRead() {
        let app = bannerApp("banner-multiple")
        XCTAssertTrue(imageElement(app, "success").waitForExistence(timeout: 10))
        imageMetrics(app, "图片请求：1；取消：0；首页读取：1")
        bannerPage(app, 1)
    }
}

extension HomeLoadTests {
    @MainActor private func assertApprovedHomeDisplay(accessibility: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-home-fixture", "valid"]
        if accessibility {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        let launched = ProcessInfo.processInfo.systemUptime
        app.launch()
        print(
            "Home display launch returned after \(ProcessInfo.processInfo.systemUptime - launched)s"
        )
        func descendants(_ node: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
            [node] + node.children.flatMap { descendants($0) }
        }
        func observe() throws -> (root: any XCUIElementSnapshot, nodes: [any XCUIElementSnapshot]) {
            let began = ProcessInfo.processInfo.systemUptime
            let root = try app.snapshot()
            let nodes = descendants(root)
            print("Home display snapshot \(ProcessInfo.processInfo.systemUptime - began)s")
            return (root, nodes)
        }
        var initial = try observe()
        let loaded = initial.nodes.contains {
            $0.elementType == .staticText && $0.identifier == "home.loaded"
        }
        XCTAssertTrue(loaded || app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        if !loaded { initial = try observe() }
        for key in ["banner", "coupon", "category"] {
            XCTAssertFalse(
                initial.nodes.contains {
                    $0.elementType == .staticText && $0.identifier == "home.section.\(key).title"
                })
        }
        let appFrame = initial.root.frame
        let scrollFrame = try XCTUnwrap(
            initial.nodes.first {
                $0.elementType == .scrollView && $0.identifier == "home.scroll"
            }
        ).frame.intersection(appFrame)
        let tabFrame = try XCTUnwrap(initial.nodes.first { $0.elementType == .tabBar }).frame
        let bottom = min(scrollFrame.maxY, tabFrame.minY) - 24
        let top = scrollFrame.minY + 40
        func reveal(
            _ identifier: String, including companionID: String? = nil
        ) throws -> (element: any XCUIElementSnapshot, companion: (any XCUIElementSnapshot)?) {
            let element = app.staticTexts[identifier]
            func pressDrag(from startY: CGFloat, to endY: CGFloat) {
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(
                        CGVector(dx: scrollFrame.midX - appFrame.minX, dy: startY - appFrame.minY)
                    )
                    .press(
                        forDuration: 0.05,
                        thenDragTo: app.coordinate(withNormalizedOffset: .zero)
                            .withOffset(
                                CGVector(
                                    dx: scrollFrame.midX - appFrame.minX, dy: endY - appFrame.minY)),
                        withVelocity: .fast, thenHoldForDuration: 0.2)
            }
            func dragDown(_ distance: CGFloat) {
                pressDrag(from: top, to: top + distance)
            }
            func dragUp(_ distance: CGFloat) {
                pressDrag(from: bottom, to: bottom - distance)
            }
            // Each iteration observes one current hierarchy after the last
            // real gesture. Missing nodes still require bounded navigation;
            // offscreen frames never count as a successful reveal.
            for _ in 0..<8 {
                let nodes = try observe().nodes
                let available = bottom - top
                guard
                    let elementSnapshot = nodes.first(where: {
                        $0.elementType == .staticText && $0.identifier == identifier
                    })
                else {
                    dragUp(available)
                    continue
                }
                let elementFrame = elementSnapshot.frame
                guard elementFrame.minY >= top, elementFrame.maxY <= bottom else {
                    print(
                        "Home display reveal anchor=\(elementFrame), viewport=\(scrollFrame)")
                    if elementFrame.minY < top {
                        dragDown(min(top - elementFrame.minY + 24, available))
                    } else {
                        dragUp(min(elementFrame.maxY - bottom + 24, available))
                    }
                    continue
                }
                guard let companionID else {
                    XCTAssertTrue(element.isHittable)
                    return (elementSnapshot, nil)
                }
                guard
                    let companionSnapshot = nodes.first(where: {
                        $0.elementType == .staticText && $0.identifier == companionID
                    })
                else {
                    dragUp(available)
                    continue
                }
                let frame = elementFrame.union(companionSnapshot.frame)
                if frame.minY >= top, frame.maxY <= bottom {
                    XCTAssertTrue(element.isHittable)
                    return (elementSnapshot, companionSnapshot)
                }
                if frame.minY < top {
                    dragDown(min(top - frame.minY + 24, available))
                } else {
                    dragUp(min(frame.maxY - bottom + 24, available))
                }
            }
            XCTAssertTrue(element.isHittable)
            let nodes = try observe().nodes
            let anchor = try XCTUnwrap(
                nodes.first {
                    $0.elementType == .staticText && $0.identifier == identifier
                })
            let companion = companionID.flatMap { id in
                nodes.first { $0.elementType == .staticText && $0.identifier == id }
            }
            return (anchor, companion)
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "home-display-\(accessibility ? "AX" : "normal")-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let couponObservation = try reveal("home.coupon.860001.title")
        let claim = app.buttons["home.coupon.860001.claim"]
        XCTAssertTrue(claim.isHittable)
        let couponFrame = couponObservation.element.frame
        let claimFrame = claim.frame
        XCTAssertLessThan(couponFrame.maxX, claimFrame.minX)
        XCTAssertTrue(couponFrame.minY < claimFrame.maxY && claimFrame.minY < couponFrame.maxY)
        XCTAssertFalse(couponObservation.element.label.isEmpty)
        capture("coupon")
        if !accessibility {
            _ = try reveal("home.flashSale.830001.title")
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
            let row = try reveal("home.\(key).\(id).sold", including: "home.\(key).\(id).price")
            XCTAssertTrue(price.isHittable)
            XCTAssertEqual(row.element.label, "已售\(sold)件")
            let priceFrame = try XCTUnwrap(row.companion).frame
            let countFrame = row.element.frame
            if accessibility, id == "830010" {
                XCTAssertLessThanOrEqual(max(priceFrame.maxY, countFrame.maxY), bottom)
            }
            print("Home display \(key) amount frame=\(priceFrame), sold frame=\(countFrame)")
            XCTAssertLessThanOrEqual(priceFrame.maxX, countFrame.minX)
            XCTAssertTrue(
                priceFrame.minY < countFrame.maxY && countFrame.minY < priceFrame.maxY,
                "price and actual sold count must share one row")
            capture(id == "830010" ? "recommend-4683" : key)
        }
    }
    @MainActor func testApprovedHomeDisplayAtNormalSize() throws {
        try assertApprovedHomeDisplay(accessibility: false)
    }
    @MainActor func testApprovedHomeDisplayAtAccessibilitySize() throws {
        try assertApprovedHomeDisplay(accessibility: true)
    }
}

extension HomeLoadTests {
    @MainActor private func assertCouponAndFeatured(accessibility: Bool) {
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
            attachment.name = "home-coupon-featured-\(accessibility ? "AX" : "normal")-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let coupon = app.staticTexts["home.coupon.860001.title"]
        reveal(coupon)
        let claim = app.buttons["home.coupon.860001.claim"]
        XCTAssertTrue(claim.isHittable)
        XCTAssertGreaterThanOrEqual(claim.frame.width, 44)
        XCTAssertGreaterThanOrEqual(claim.frame.height, 44)
        XCTAssertLessThan(coupon.frame.maxX, claim.frame.minX)
        XCTAssertTrue(coupon.frame.minY < claim.frame.maxY && claim.frame.minY < coupon.frame.maxY)
        XCTAssertFalse(coupon.label.isEmpty)
        let claimFrame = claim.frame
        coupon.swipeLeft()
        let nextClaim = app.buttons["home.coupon.860002.claim"]
        XCTAssertTrue(nextClaim.waitForExistence(timeout: 8))
        XCTAssertEqual(nextClaim.frame.minX, claimFrame.minX, accuracy: 1)
        XCTAssertEqual(nextClaim.frame.minY, claimFrame.minY, accuracy: 1)
        XCTAssertTrue(nextClaim.label.contains("小米家电"))
        capture("coupon-current-second")
        XCTAssertTrue(app.staticTexts["home.loaded"].exists)
        XCTAssertEqual(app.staticTexts["home.count.coupon"].label, "优惠券：3")
        app.tabBars.buttons["分类"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertTrue(nextClaim.exists)
        XCTAssertEqual(nextClaim.frame.minX, claimFrame.minX, accuracy: 1)
        XCTAssertEqual(nextClaim.frame.minY, claimFrame.minY, accuracy: 1)
        app.staticTexts["home.coupon.860002.title"].swipeRight()
        XCTAssertTrue(claim.waitForExistence(timeout: 8))
        capture("coupon")
        reveal(app.staticTexts["home.flashSale.830001.title"])
        XCTAssertFalse(app.staticTexts["home.flashSale.830001.sold"].exists)
        // Align the actual section top inside the real viewport so all four
        // white-container insets can be reviewed, including at AX sizes.
        let homeScroll = app.scrollViews["home.scroll"]
        let sectionHeader = app.staticTexts["home.section.flashSale.title"]
        for _ in 0..<2 {
            let viewport = homeScroll.frame
            let top = viewport.minY + 12
            let bottom = min(viewport.maxY, app.tabBars.firstMatch.frame.minY) - 12
            let delta = sectionHeader.frame.minY - 12 - top
            if abs(delta) <= 2 { break }
            let startY = delta > 0 ? bottom - 20 : top + 20
            let distance = min(abs(delta), (bottom - top) * 0.8)
            let endY = startY + (delta > 0 ? -distance : distance)
            let origin = homeScroll.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: viewport.width * 0.98, dy: startY - viewport.minY))
                .press(
                    forDuration: 0.05,
                    thenDragTo: origin.withOffset(
                        CGVector(dx: viewport.width * 0.98, dy: endY - viewport.minY)),
                    withVelocity: 500, thenHoldForDuration: 0.2)
        }
        capture("featured")
        let firstFeatured = app.buttons["home.flashSale.830001.card"]
        let initialFeaturedX = firstFeatured.frame.minX
        app.scrollViews["home.flashSale.items"].swipeLeft()
        XCTAssertLessThan(firstFeatured.frame.minX, initialFeaturedX)
        XCTAssertEqual(app.staticTexts["home.count.flashSale"].label, "限时精选：8")
        capture("featured-scrolled")
    }
    @MainActor func testCouponAndFeaturedAtNormalSize() {
        assertCouponAndFeatured(accessibility: false)
    }
    @MainActor func testCouponAndFeaturedAtAccessibilitySize() {
        assertCouponAndFeatured(accessibility: true)
    }
}

/// Genuine five-second autoplay coverage. These deliberately launch WITHOUT
/// the manual gate: the real cadence, not a controlled pause, is under test.
/// Exact deadline arithmetic (5s, stale wakes, no catch-up, 0/1 banners) is
/// covered by the deterministic HomeBannerAutoplay/Gate unit tests. Timing is
/// asserted by MEASURING the advance from a hard anchor (the gesture/tap
/// return), because a fixed negative window sampled after activation can
/// race the correct arm point.
extension HomeLoadTests {
    @MainActor private func waitQuiet(_ seconds: TimeInterval) {
        // An always-false inverted expectation waits the full window without
        // polling the application under test.
        let quiet = XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)
        quiet.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [quiet], timeout: seconds), .completed)
    }

    @MainActor private func indicatorPage(_ app: XCUIApplication) -> String {
        bannerIndicators(app).value as? String ?? ""
    }

    /// Wait for the first pagination change away from `page` and return the
    /// newly shown page. AX polling lag only delays detection, never advances
    /// it, so elapsed measurements stay valid lower bounds.
    @MainActor private func waitAdvance(
        _ app: XCUIApplication, from page: String, timeout: TimeInterval = 10
    ) -> String {
        let indicators = bannerIndicators(app)
        var observed = page
        let advanced = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let value = indicators.value as? String ?? ""
                if !value.isEmpty, value != page { observed = value }
                return !value.isEmpty && value != page
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [advanced], timeout: timeout), .completed,
            "autoplay must advance away from \(page)")
        return observed
    }

    /// One real short horizontal drag below the paging threshold. It must
    /// keep the current page while held; the return value anchors the
    /// re-arm measurement at the release instant. The press uses STATIC
    /// app-relative coordinates: an element-derived coordinate is re-resolved
    /// against the live AX tree during the press (and across the wrap
    /// animation), which on a slow runner delayed the synthesized touch past
    /// the pending five-second deadline (R-AUTO-01: the wrap then fired
    /// before any touch existed). The banner is stationary once revealed, so
    /// a single frame lookup converted to app fractions is enough.
    @discardableResult
    @MainActor private func unchangedDrag(_ app: XCUIApplication, hold: TimeInterval) -> Date {
        let frame = currentBanner(app).frame
        let appFrame = app.frame
        let center = CGVector(
            dx: (frame.midX - appFrame.minX) / appFrame.width,
            dy: (frame.midY - appFrame.minY) / appFrame.height)
        let shifted = CGVector(dx: center.dx + 0.02, dy: center.dy)
        app.coordinate(withNormalizedOffset: center).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: shifted),
            withVelocity: .slow, thenHoldForDuration: hold)
        return Date()
    }

    @MainActor func testBannerAutoplayCyclesAndRestartsAfterUnchangedDrag() {
        continueAfterFailure = false
        let app = bannerApp("banner-multiple", automatic: true)
        revealBanner(app)
        XCTAssertFalse(app.staticTexts["home.banner.page"].exists)
        XCTAssertFalse(app.buttons["home.banner.previous"].exists)
        XCTAssertFalse(app.buttons["home.banner.next"].exists)
        XCTAssertTrue(bannerIndicators(app).exists, "multiple banners show in-image dots")
        // Synchronize on one genuine cold-start advance so later intervals
        // are measured from a known fresh arm, not from launch overhead.
        let coldStart = Date()
        let heldPage = waitAdvance(app, from: indicatorPage(app), timeout: 15)
        print("autoplay cold-start advance after \(Date().timeIntervalSince(coldStart))s")
        // The leaf's AX exposure can lag the indicator value by a beat right
        // after an advance; settle before treating the leaf as the baseline.
        waitQuiet(0.8)
        let baseline = currentBanner(app).identifier
        let released = unchangedDrag(app, hold: 1)
        XCTAssertEqual(currentBanner(app).identifier, baseline, "unchanged drag keeps the page")
        waitAdvance(app, from: heldPage)
        let rearmElapsed = Date().timeIntervalSince(released)
        XCTAssertGreaterThanOrEqual(
            rearmElapsed, 4.5, "release must re-arm one full five-second interval")
        XCTAssertLessThanOrEqual(rearmElapsed, 9)
        // Two more genuine advances from the CURRENT page complete the
        // approved wrap back to the page held before the drag.
        var page = indicatorPage(app)
        page = waitAdvance(app, from: page)
        page = waitAdvance(app, from: page)
        XCTAssertEqual(page, heldPage, "three advances wrap back to the held page")
        // Both public AX surfaces must agree after the wrap settles: the leaf
        // exposure can trail the indicator value by one AX beat.
        let baselineID = String(baseline.dropFirst("home.banner.current.".count))
        let wrappedLeaf = app.descendants(matching: .any)[
            "home.banner.current.\(baselineID)"
        ].firstMatch
        XCTAssertTrue(wrappedLeaf.waitForExistence(timeout: 2), "wrapped page leaf must be exposed")
        keepFeedbackScreenshot(app, name: "HOME-AUTO-image-dots-cycle")
    }

    /// Consistent AX baseline; this does not establish a fresh timer period.
    /// the indicator value updates promptly while the leaf's AX exposure lags
    /// an advance, so retry briefly until both surfaces agree on one page.
    /// banner-multiple order: 910001…910003 = pages 1…3.
    @MainActor private func syncedCurrentLeafID(_ app: XCUIApplication) -> String? {
        for _ in 0..<4 {
            let page = indicatorPage(app)
            let id = currentBanner(app).identifier
            if let p = page.firstMatch(of: /第(\d+)页/), let n = Int(p.1),
                id == "home.banner.current.\(910_000 + n)"
            {
                return id
            }
            waitQuiet(0.5)
        }
        return nil
    }

    @MainActor func testBannerAutoplayPausesWhileAwayAndResumesFullInterval() {
        continueAfterFailure = false
        // APPROVAL-AWAY-BUSY-120-20261019: several mandated five-second waits
        // plus two away windows exceed the default allowance on slow runners.
        executionTimeAllowance = 120
        let app = bannerApp("banner-multiple", automatic: true)
        revealBanner(app)
        // Cache geometry before establishing a fresh timer period. No dynamic
        // element lookup is needed when the native tab touch is delivered.
        let appFrame = app.frame
        let bannerFrame = currentBanner(app).frame
        func point(_ location: CGPoint) -> XCUICoordinate {
            app.coordinate(
                withNormalizedOffset: CGVector(
                    dx: (location.x - appFrame.minX) / appFrame.width,
                    dy: (location.y - appFrame.minY) / appFrame.height))
        }
        // Horizontal paging may translate the leaf; the application center stays fixed.
        let dragStart = point(CGPoint(x: appFrame.midX, y: bannerFrame.midY))
        let dragEnd = point(
            CGPoint(
                x: appFrame.midX + appFrame.width * 0.02, y: bannerFrame.midY))
        let categoryFrame = app.tabBars.buttons["分类"].frame
        let homeFrame = app.tabBars.buttons["首页"].frame
        let categoryTab = point(CGPoint(x: categoryFrame.midX, y: categoryFrame.midY))
        let homeTab = point(CGPoint(x: homeFrame.midX, y: homeFrame.midY))
        @discardableResult
        func stableBannerDrag(hold: TimeInterval) -> Date {
            // A newly selected leaf can still have an offscreen animation
            // frame. Touch the stationary banner region cached above instead.
            dragStart.press(
                forDuration: 0.05, thenDragTo: dragEnd,
                withVelocity: .slow, thenHoldForDuration: hold)
            return Date()
        }
        // This anchor precedes the real release/re-arm. Confirming departure
        // within five seconds excludes expiry between baseline and departure.
        let tabDepartureStarted = ProcessInfo.processInfo.systemUptime
        stableBannerDrag(hold: 0.1)
        guard let baseline = syncedCurrentLeafID(app) else {
            XCTFail("indicator and leaf never agreed on one page")
            return
        }
        // Away on another tab for MORE than one interval: any pre-leave arm's
        // deadline falls inside the away window, so a still-running timer
        // would have advanced exactly once by the time home returns.
        categoryTab.tap()
        let categoryLoaded = app.staticTexts["category.pending"]
        XCTAssertTrue(categoryLoaded.exists || categoryLoaded.waitForExistence(timeout: 5))
        let tabPreparationSeconds = ProcessInfo.processInfo.systemUptime - tabDepartureStarted
        XCTContext.runActivity(named: "Tab departure prepared in \(tabPreparationSeconds)s (<5s)") {
            _ in
            XCTAssertLessThan(
                tabPreparationSeconds, 5,
                "driver precondition: confirm departure before the fresh period expires")
        }
        waitQuiet(5.6)
        homeTab.tap()
        // ORIGINAL timing scope (R-LATEST-04): sample the anchor immediately
        // after the tap returns, BEFORE the currentBanner AX query, so the
        // original bounds cover the query too.
        let returned = Date()
        XCTAssertEqual(currentBanner(app).identifier, baseline, "no advance while away")
        let resumedPage = waitAdvance(app, from: indicatorPage(app))
        let tabElapsed = Date().timeIntervalSince(returned)
        XCTAssertGreaterThanOrEqual(tabElapsed, 3.0, "timer must resume after tab return")
        XCTAssertLessThanOrEqual(tabElapsed, 9)
        // Expected leaf derived from the JUST-OBSERVED indicator page: no
        // lagging leaf read may sit between the anchor and the drag.
        guard let page = resumedPage.firstMatch(of: /第(\d+)页/), let pageNumber = Int(page.1)
        else {
            XCTFail("unexpected indicator page value: \(resumedPage)")
            return
        }
        let resumedLeafID = "home.banner.current.\(910_000 + pageNumber)"
        let tabReleased = stableBannerDrag(hold: 0.5)
        XCTAssertEqual(
            currentBanner(app).identifier, resumedLeafID, "unchanged drag keeps the page")
        waitAdvance(app, from: indicatorPage(app))
        let tabRearmElapsed = Date().timeIntervalSince(tabReleased)
        XCTAssertGreaterThanOrEqual(
            tabRearmElapsed, 4.4, "release in the resumed state must re-arm a full interval")
        XCTAssertLessThanOrEqual(tabRearmElapsed, 9)
        // Scene backgrounding pauses the same way and preserves selection.
        let sceneDepartureStarted = ProcessInfo.processInfo.systemUptime
        stableBannerDrag(hold: 0.1)
        guard let beforeBackground = syncedCurrentLeafID(app) else {
            XCTFail("indicator and leaf never agreed before backgrounding")
            return
        }
        XCUIDevice.shared.press(.home)
        let backgrounded = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.state != .runningForeground }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [backgrounded], timeout: 5), .completed,
            "the simulated home press must actually background the app")
        let scenePreparationSeconds = ProcessInfo.processInfo.systemUptime - sceneDepartureStarted
        XCTContext.runActivity(named: "Background prepared in \(scenePreparationSeconds)s (<5s)") {
            _ in
            XCTAssertLessThan(
                scenePreparationSeconds, 5,
                "driver precondition: confirm backgrounding before the fresh period expires")
        }
        waitQuiet(5.6)
        app.activate()
        let foregrounded = Date()
        // ONE early preserved read: the resumed timer legitimately advances
        // five seconds after activation, and a slow post-restart read can land
        // after that advance, so a second (indicator) preserved read is racy.
        XCTAssertEqual(currentBanner(app).identifier, beforeBackground)
        waitAdvance(app, from: indicatorPage(app))
        let sceneElapsed = Date().timeIntervalSince(foregrounded)
        XCTAssertGreaterThanOrEqual(sceneElapsed, 3.0, "timer must resume after foregrounding")
        XCTAssertLessThanOrEqual(sceneElapsed, 9)
    }

    @MainActor func testBannerAutoplayPausesWhileBannerIsOffscreen() {
        continueAfterFailure = false
        let app = bannerApp("banner-multiple", automatic: true)
        revealBanner(app)
        XCTAssertTrue(currentBanner(app).isHittable)
        let scroll = app.scrollViews["home.scroll"].frame.intersection(app.frame)
        func bannerAboveViewport() -> Bool {
            currentBanner(app).frame.maxY < scroll.minY
        }
        // Fast real side drags move the banner fully above the viewport. An
        // advance DURING the scroll-out (banner still partially visible) is
        // legal, so the baseline is captured only once the banner is fully
        // gone — exactly the interval this test guards. This also drops the
        // old cold-start sync advance, whose five-second wait pushed the
        // method's CI budget over the deadline.
        for _ in 0..<4 where !bannerAboveViewport() {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.42))
            start.press(
                forDuration: 0.01, thenDragTo: end, withVelocity: 10_000, thenHoldForDuration: 0)
        }
        XCTAssertTrue(bannerAboveViewport(), "banner must be scrolled fully offscreen")
        guard let offscreenLeafID = syncedCurrentLeafID(app) else {
            XCTFail("indicator and leaf never agreed while offscreen")
            return
        }
        waitQuiet(6.2)
        for _ in 0..<6 {
            if currentBanner(app).isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.42))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.75))
            start.press(
                forDuration: 0.01, thenDragTo: end, withVelocity: 10_000, thenHoldForDuration: 0)
        }
        XCTAssertTrue(currentBanner(app).isHittable)
        XCTAssertEqual(
            currentBanner(app).identifier, offscreenLeafID,
            "the paused timer must not advance while the banner is fully offscreen")
        // Mirror the away test's post-return segment: a legal deadline may
        // separate the return from the drag on a slow runner (the old
        // pre-touch baseline raced it — the CI offscreen failure), so re-arm
        // the phase explicitly and derive the expected leaf from the
        // JUST-OBSERVED indicator page.
        let resumedPage = waitAdvance(app, from: indicatorPage(app))
        guard let page = resumedPage.firstMatch(of: /第(\d+)页/), let pageNumber = Int(page.1)
        else {
            XCTFail("unexpected indicator page value: \(resumedPage)")
            return
        }
        let resumedLeafID = "home.banner.current.\(910_000 + pageNumber)"
        let released = unchangedDrag(app, hold: 0.5)
        XCTAssertEqual(
            currentBanner(app).identifier, resumedLeafID, "unchanged drag keeps the page")
        waitAdvance(app, from: indicatorPage(app))
        let elapsed = Date().timeIntervalSince(released)
        XCTAssertGreaterThanOrEqual(elapsed, 4.4, "release must re-arm a full interval")
        XCTAssertLessThanOrEqual(elapsed, 9)
    }

    /// The seeded pushed route keeps home inactive from launch; popping back
    /// must arm one full fresh interval with no catch-up burst. Existing
    /// nav-control seams only — no new product route or test button.
    @MainActor func testBannerAutoplayArmsAfterPushedRoutePopsBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-home-fixture", "banner-multiple", "--uitest-nav-control",
            "--uitest-nav-paths", "home=probe",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.probeIdentity"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let popped = Date()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        revealBanner(app)
        XCTAssertEqual(
            currentBanner(app).identifier, "home.banner.current.910001",
            "home was inactive for the whole pushed period")
        waitAdvance(app, from: indicatorPage(app), timeout: 15)
        let elapsed = Date().timeIntervalSince(popped)
        XCTAssertGreaterThanOrEqual(
            elapsed, 4.4, "popping must arm one full fresh interval, not a catch-up burst")
        XCTAssertLessThanOrEqual(elapsed, 14)
    }
}
