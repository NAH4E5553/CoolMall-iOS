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
    @MainActor func testEmptyInputsShowNoSectionsAndKeepEmptyEvidence() {
        let inputs: [(mode: String, auxiliary: String)] = [
            ("empty", "0"), ("empty-category", "3"),
        ]
        for input in inputs {
            let app = XCUIApplication()
            app.launchArguments += ["--ui-home-fixture", input.mode]
            app.launch()
            XCTAssertTrue(app.staticTexts["home.empty"].waitForExistence(timeout: 10))
            for section in Self.orderedSections {
                XCTAssertFalse(
                    app.staticTexts["home.section.\(section.key).title"].exists,
                    "\(section.key) title must not appear for \(input.mode)")
                XCTAssertFalse(
                    app.staticTexts["home.section.\(section.key).pending"].exists,
                    "\(section.key) placeholder must not appear for \(input.mode)")
            }
            XCTAssertEqual(
                app.staticTexts["home.count.categoryAll"].label, "完整分类（辅助）：\(input.auxiliary)")
            XCTAssertTrue(app.buttons["home.retry"].exists)
            app.terminate()
        }
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

    /// AT-HOME-02-04 (re-tap): three re-taps of the current home tab keep the
    /// committed content with no reload (no loading flash, no content change).
    /// PLATFORM CONSTRAINT (disclosed in the handoff, PRD-016 precedent): iOS
    /// also scrolls a tab's scroll view toward the top on a tab re-tap — the
    /// same un-vetoable system behavior family as the iOS 18 re-tap auto-pop.
    /// The scroll-position part of "重按不回顶" therefore cannot be asserted
    /// here and is pending the maintainer's decision; the no-refresh part IS
    /// enforced, and the zero-construction/zero-call evidence comes from a
    /// temporary instrumented copy.
    @MainActor func testReTapKeepsCommittedContentWithoutReload() {
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
        let bannerLabelBefore = app.staticTexts["home.count.banner"].label
        for _ in 1...3 {
            app.tabBars.buttons["首页"].tap()
            usleep(600_000)
            // No reload: the committed ready state stays; no loading flash.
            XCTAssertTrue(app.staticTexts["home.loaded"].exists, "re-tap must not re-enter loading")
            XCTAssertFalse(app.staticTexts["home.loading"].exists)
            XCTAssertEqual(
                app.staticTexts["home.count.banner"].label, bannerLabelBefore,
                "re-tap must not refresh content")
        }
        // The scrolled-to row stays reachable in the scrollable content after
        // the system's re-tap scroll settles.
        for _ in 0..<4 {
            if lastRow.exists, lastRow.isHittable { break }
            app.swipeUp(velocity: .fast)
            usleep(500_000)
        }
        XCTAssertTrue(lastRow.isHittable)
    }
}
