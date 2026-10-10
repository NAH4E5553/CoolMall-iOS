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

    @MainActor func testEmptyFixtureShowsCountsAndRetryStaysEmpty() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "empty"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 10))
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
        app.buttons["home.retry"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.count.flashSale"].label, "限时精选：1")
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
    /// through to the real HTTP service.
    @MainActor func testMissingOrUnknownFixtureValueStopsWithConfigError() {
        let cases: [[String]] = [
            ["--ui-home-fixture"],
            ["--ui-home-fixture", "--uitest-nav-fixture"],
            ["--ui-home-fixture", "bogus"],
        ]
        for arguments in cases {
            let app = XCUIApplication()
            app.launchArguments += arguments
            app.launch()
            XCTAssertTrue(
                app.staticTexts["home.testConfigError"].waitForExistence(timeout: 10),
                "expected config error for \(arguments)")
            XCTAssertFalse(app.staticTexts["home.loaded"].waitForExistence(timeout: 2))
            XCTAssertFalse(app.staticTexts["home.error"].waitForExistence(timeout: 2))
            app.terminate()
        }
    }
}

/// HOME-02 section-skeleton coverage (AT-HOME-02-01…04). Ordering assertions
/// scroll through the content and record when each title first becomes
/// hittable; empty-section hiding is structural (the elements never exist).
extension HomeLoadTests {
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
        // All six titles and placeholders exist for the all-non-empty input.
        for section in Self.orderedSections {
            XCTAssertTrue(
                app.staticTexts["home.section.\(section.key).title"].exists,
                "\(section.key) title must exist for valid input")
            XCTAssertTrue(
                app.staticTexts["home.section.\(section.key).pending"].exists,
                "\(section.key) placeholder must exist for valid input")
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
            app.staticTexts["home.section.\(section.key).title"].frame
        }
        for index in 1..<titleFrames.count {
            XCTAssertLessThan(
                titleFrames[index - 1].minY, titleFrames[index].minY,
                "\(Self.orderedSections[index - 1].key) must sit above \(Self.orderedSections[index].key)"
            )
        }
        // Left alignment at the shared 16pt margin: all title leading edges
        // line up regardless of text length.
        let leading = titleFrames[0].minX
        for (index, frame) in titleFrames.enumerated() {
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
                app.staticTexts["home.section.\(key).pending"].exists,
                "\(key) placeholder and reserved area must be hidden")
        }
        for key in ["coupon", "flashSale", "recommend", "goods"] {
            XCTAssertTrue(app.staticTexts["home.section.\(key).title"].exists)
            XCTAssertTrue(app.staticTexts["home.section.\(key).pending"].exists)
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
    private func assertEmptyInputShowsNoSections(
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
                app.staticTexts["home.section.\(section.key).pending"].exists,
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
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "valid"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        let lastRow = app.staticTexts["home.count.categoryAll"]
        for _ in 0..<8 {
            if lastRow.exists, lastRow.isHittable { break }
            app.swipeUp(velocity: .fast)
            usleep(500_000)
        }
        XCTAssertTrue(lastRow.isHittable, "auxiliary last row must be reachable by scrolling")
        // Let the scroll settle before recording the reference position.
        usleep(600_000)
        let referenceMinY = lastRow.frame.minY
        let bannerLabelBefore = app.staticTexts["home.count.banner"].label

        for round in 1...2 {
            app.tabBars.buttons["分类"].tap()
            usleep(700_000)
            app.tabBars.buttons["首页"].tap()
            XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
            app.tabBars.buttons["购物车"].tap()
            usleep(700_000)
            app.tabBars.buttons["首页"].tap()
            XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
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
        let bannerTitle = app.staticTexts["home.section.banner.title"]
        let lastRow = app.staticTexts["home.count.categoryAll"]
        // The content only slightly overflows one screen, so "scrolled away
        // from the top" is asserted by FRAME POSITION, not by visibility.
        let atRestMinY = lastRow.frame.minY
        for _ in 0..<10 where !(lastRow.exists && lastRow.isHittable) {
            app.swipeUp(velocity: .fast)
            usleep(400_000)
        }
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
        let scrollToTopMinY = lastRow.frame.minY
        // The scrollTo anchor alignment sits slightly above the fully
        // expanded large-title resting position (bar/inset dependent — ~68pt
        // at large, ~101pt at AX), so only a loose bound is asserted here;
        // the deterministic assertions are the banner visibility and the
        // second re-tap landing on the SAME position.
        XCTAssertGreaterThan(
            scrollToTopMinY, atRestMinY - 160,
            "re-tap must land near the resting (top) position")
        // Real re-tap #2 while ALREADY AT TOP (AT: 停在顶部再按→C): a re-tap
        // at the top also refreshes, and the position stays put.
        app.tabBars.buttons["首页"].tap()
        let cSeen = NSPredicate(format: "label CONTAINS %@", "全部商品：12")
        expectation(for: cSeen, evaluatedWith: goods)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(bannerTitle.isHittable)
        XCTAssertEqual(
            lastRow.frame.minY, scrollToTopMinY, accuracy: 6,
            "an at-top re-tap must keep the same fixed top-anchor position")
    }

    /// Re-taps while a refresh hangs: only scroll-to-top, no second request,
    /// no restart, no queued catch-up; leaving the page cancels the refresh;
    /// returning keeps the old content without an implicit re-fire; a NEW
    /// re-tap after returning is accepted again.
    @MainActor func testReTapDuringPendingRefreshDoesNotStackAndLeaveCancels() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-home-fixture", "retap-pending"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        let bannerTitle = app.staticTexts["home.section.banner.title"]
        for _ in 0..<8 where bannerTitle.isHittable {
            app.swipeUp(velocity: .fast)
            usleep(400_000)
        }
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        for _ in 1...3 {
            app.tabBars.buttons["首页"].tap()
            usleep(800_000)
            XCTAssertTrue(
                app.staticTexts["home.refreshing"].exists,
                "refresh must still be the single pending one")
            XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        }
        XCTAssertTrue(bannerTitle.isHittable, "re-tap scrolls to top even while busy")
        // Leave the page mid-refresh: the request is cancelled, the indicator
        // closes, the old content stays and returning does not re-fire.
        app.tabBars.buttons["分类"].tap()
        usleep(800_000)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["home.refreshing"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["home.count.goods"].label, "全部商品：10")
        // A new explicit re-tap is accepted (the pending service hangs again).
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["home.refreshing"].waitForExistence(timeout: 10))
        app.tabBars.buttons["分类"].tap()
        usleep(400_000)
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
        app.buttons["home.refresh.retry"].tap()
        let bSeen = NSPredicate(format: "label CONTAINS %@", "全部商品：11")
        expectation(for: bSeen, evaluatedWith: app.staticTexts["home.count.goods"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.staticTexts["home.refresh.failed"].exists)
    }
}
