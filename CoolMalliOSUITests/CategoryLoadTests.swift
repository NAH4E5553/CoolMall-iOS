import XCTest

/// CATEGORY-01 minimal device checks over the controlled category fixture:
/// three-column group layout, real direct-child ids, the left/right scroll
/// linkage without a loop, the empty/error/retry states and first-load
/// feedback. Fixtures stay offline (nil images); no home HTTP is involved
/// because the deterministic home fixture is selected in the same launch.
final class CategoryLoadTests: XCTestCase {
    private static let rootIDs: [Int64] = [
        800_001, 800_002, 800_003, 800_004, 800_005, 800_006, 800_099,
    ]

    @MainActor private func launch(categoryFixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-home-fixture", "valid",
            "--ui-category-fixture", categoryFixture,
        ]
        app.launch()
        return app
    }

    @MainActor private func openCategory(_ app: XCUIApplication) {
        app.tabBars.buttons["分类"].tap()
    }

    @MainActor private func wait(
        _ condition: () -> Bool, timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Selected root read from the DEBUG read-verification marker (the page
    /// model's real selection, not a title-position heuristic).
    @MainActor private func selectedRoot(_ app: XCUIApplication) -> Int64? {
        let marker = app.staticTexts["category.selected"]
        guard marker.exists else { return nil }
        return Int64(marker.label.filter(\.isNumber))
    }

    @MainActor func testThreeColumnLayoutRealChildIDsAndLeftTapScrollLink() {
        let app = launch(categoryFixture: "valid")
        openCategory(app)

        let firstRoot = app.buttons["category.root.800001"]
        XCTAssertTrue(firstRoot.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["category.loaded"].exists)
        XCTAssertEqual(app.staticTexts["category.count.roots"].label, "一级分类：7")
        XCTAssertEqual(app.staticTexts["category.count.children"].label, "直接子分类：22")
        XCTAssertTrue(firstRoot.isSelected, "the first root starts selected")
        XCTAssertEqual(selectedRoot(app), 800_001)

        // Deeper and unknown-parent nodes are never rendered as subcategories.
        XCTAssertFalse(app.buttons["category.sub.801099"].exists)
        XCTAssertFalse(app.buttons["category.sub.801098"].exists)

        // Android 3-column grid: the first three direct children share one row
        // with equal widths and increasing x.
        let first = app.buttons["category.sub.801001"]
        let second = app.buttons["category.sub.801002"]
        let third = app.buttons["category.sub.801003"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(third.exists)
        // Reference rows center their cells vertically; a wrapped name makes
        // the first cell taller, so compare vertical centers, not tops.
        XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 1)
        XCTAssertEqual(second.frame.midY, third.frame.midY, accuracy: 1)
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertEqual(second.frame.width, third.frame.width, accuracy: 1)
        XCTAssertLessThan(first.frame.minX, second.frame.minX)
        XCTAssertLessThan(second.frame.minX, third.frame.minX)

        attach(app, name: "category-valid-layout")

        // Left tap scrolls the right pane to that root and highlights it.
        let targetRoot = app.buttons["category.root.800005"]
        XCTAssertTrue(targetRoot.exists)
        targetRoot.tap()
        let targetTitle = app.staticTexts["category.group.800005.title"]
        XCTAssertTrue(targetTitle.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["category.right.scroll"]
        XCTAssertTrue(scroll.exists)
        XCTAssertTrue(
            wait({ abs(targetTitle.frame.minY - scroll.frame.minY) <= 24 }, timeout: 5),
            "the tapped group reaches the top of the right pane")
        XCTAssertTrue(targetRoot.isSelected, "the left rail highlights the tapped root")
        XCTAssertEqual(selectedRoot(app), 800_005)

        // No feedback loop: the left highlight update must not scroll again.
        let settledY = targetTitle.frame.minY
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(targetTitle.frame.minY, settledY, accuracy: 2)
        XCTAssertTrue(targetRoot.isSelected)

        // Right scroll syncs the left highlight to the first group whose content
        // still intersects the viewport top (Android firstVisibleItemIndex).
        // Group spacing is 24pt, so the previous group's bottom is the selected
        // title's top minus 24pt.
        let beforeSwipe = selectedRoot(app)
        scroll.swipeUp()
        XCTAssertTrue(
            wait({ selectedRoot(app) != beforeSwipe }, timeout: 6),
            "right scrolling changes the left selection")
        guard let selected = selectedRoot(app),
            let index = Self.rootIDs.firstIndex(of: selected)
        else {
            XCTFail("no selected root after scrolling")
            return
        }
        let selectedTitle = app.staticTexts["category.group.\(selected).title"]
        XCTAssertTrue(selectedTitle.exists)
        if index > 0 {
            let previousBottom = selectedTitle.frame.minY - 24
            XCTAssertLessThanOrEqual(
                previousBottom, scroll.frame.minY + 2,
                "the previous group must already be above the viewport top")
        }
        if index + 1 < Self.rootIDs.count {
            let nextTitle = app.staticTexts["category.group.\(Self.rootIDs[index + 1]).title"]
            let selectedBottom = nextTitle.frame.minY - 24
            XCTAssertGreaterThan(
                selectedBottom, scroll.frame.minY,
                "the selected group must still intersect the viewport top")
        }
        // No feedback loop: the scroll-driven selection must not scroll again.
        let stableY = selectedTitle.frame.minY
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(selectedTitle.frame.minY, stableY, accuracy: 2)
        XCTAssertEqual(selectedRoot(app), selected)
        XCTAssertTrue(app.buttons["category.root.\(selected)"].isSelected)
        attach(app, name: "category-valid-linked")

        // R-CATEGORY-01-01 minimal repro: the ADJACENT previous group is
        // likely just above the right viewport and still in the realized frame
        // cache. Tapping its left root must scroll it back to the top; the old
        // `minY <= topInset` shortcut skipped this because minY was negative.
        if index > 0 {
            let previousRootID = Self.rootIDs[index - 1]
            let previousRoot = app.buttons["category.root.\(previousRootID)"]
            XCTAssertTrue(previousRoot.exists)
            let previousTitle = app.staticTexts["category.group.\(previousRootID).title"]
            let beforePreviousY: CGFloat? = previousTitle.exists ? previousTitle.frame.minY : nil
            previousRoot.tap()
            XCTAssertTrue(wait({ selectedRoot(app) == previousRootID }, timeout: 6))
            XCTAssertTrue(
                wait({ abs(previousTitle.frame.minY - scroll.frame.minY) <= 24 }, timeout: 5),
                "an adjacent previous root tap must scroll the target back to the top")
            if let beforePreviousY {
                XCTAssertGreaterThan(
                    previousTitle.frame.minY, beforePreviousY + 1,
                    "the right pane moved down to the adjacent previous group")
            }
            attach(app, name: "category-valid-adjacent-previous")
        }

        // R-CATEGORY-01-01 regression: a LATER -> EARLIER root tap must really
        // scroll the right pane back to the target, not only move the highlight.
        let backwardRoot = app.buttons["category.root.800002"]
        XCTAssertTrue(backwardRoot.exists)
        let beforeTitle = app.staticTexts["category.group.800002.title"]
        let beforeY: CGFloat? = beforeTitle.exists ? beforeTitle.frame.minY : nil
        backwardRoot.tap()
        XCTAssertTrue(wait({ selectedRoot(app) == 800_002 }, timeout: 6))
        let backwardTitle = app.staticTexts["category.group.800002.title"]
        XCTAssertTrue(backwardTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(
            wait({ abs(backwardTitle.frame.minY - scroll.frame.minY) <= 24 }, timeout: 5),
            "a backward root tap actually positions the target at the top")
        if let beforeY {
            XCTAssertGreaterThan(
                backwardTitle.frame.minY, beforeY + 1,
                "the right pane moved down to the earlier group")
        }
        // The target group's real content is visible with it, not just a title.
        let backwardChild = app.buttons["category.sub.801008"]
        XCTAssertTrue(backwardChild.waitForExistence(timeout: 5))
        XCTAssertLessThan(backwardChild.frame.midY, scroll.frame.maxY)
        XCTAssertTrue(backwardRoot.isSelected)
        XCTAssertEqual(selectedRoot(app), 800_002)

        // F-CATEGORY-05 navigation contract only, checked LAST so the
        // placeholder feedback's transient timer cannot disturb any scroll
        // assertion: the controlled DEBUG consumer records the real
        // direct-child id passed to the approved Int64 callback. The
        // unavailable placeholder and LIST-01 are NOT asserted (DEC-014).
        backwardChild.tap()
        XCTAssertTrue(
            wait(
                { app.staticTexts["category.requestedChild"].label == "请求子分类：801008" },
                timeout: 5),
            "the Int64 callback receives the real direct-child id")
    }

    /// The real Entry/Tab wiring: a normal Tab return keeps the retained
    /// snapshot, selection and right-pane position and does NOT re-read. The
    /// fixture returns a distinct 3-root tree on any later read, so a re-read
    /// is observable as a root-count change.
    @MainActor func testTabReturnRetainsSelectionAndDoesNotReRead() {
        let app = launch(categoryFixture: "tab-return")
        openCategory(app)
        XCTAssertTrue(app.buttons["category.root.800001"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["category.count.roots"].label, "一级分类：7")

        app.buttons["category.root.800002"].tap()
        XCTAssertTrue(wait({ selectedRoot(app) == 800_002 }, timeout: 6))
        let scroll = app.scrollViews["category.right.scroll"]
        let title = app.staticTexts["category.group.800002.title"]
        XCTAssertTrue(
            wait({ abs(title.frame.minY - scroll.frame.minY) <= 24 }, timeout: 5),
            "the selected group reaches the top before leaving")

        app.tabBars.buttons["首页"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.tabBars.buttons["分类"].tap()

        XCTAssertTrue(app.staticTexts["category.count.roots"].waitForExistence(timeout: 10))
        XCTAssertEqual(
            app.staticTexts["category.count.roots"].label, "一级分类：7",
            "a normal Tab return must not re-read (a re-read returns 3 roots)")
        XCTAssertTrue(wait({ selectedRoot(app) == 800_002 }, timeout: 5), "selection retained")
        XCTAssertTrue(
            wait({ abs(title.frame.minY - scroll.frame.minY) <= 24 }, timeout: 5),
            "right-pane scroll position retained")
        XCTAssertTrue(app.buttons["category.root.800002"].isSelected)
    }

    /// Leaving during the first read and returning must cancel or generation-
    /// reject the late first result: the first call would return a distinct
    /// 2-root tree after 3s, while the second call returns the 7-root tree.
    @MainActor func testLeaveDuringReadCancelsAndStaleResultDoesNotCommit() {
        let app = launch(categoryFixture: "slow-sequence")
        openCategory(app)
        XCTAssertTrue(
            app.staticTexts["category.loading.message"].waitForExistence(timeout: 10))

        app.tabBars.buttons["首页"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.tabBars.buttons["分类"].tap()

        XCTAssertTrue(app.staticTexts["category.count.roots"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["category.count.roots"].label, "一级分类：7")
        // Wait past the first read's 10s deadline: its 2-root tree must never
        // replace the newer read.
        RunLoop.current.run(until: Date().addingTimeInterval(10.5))
        XCTAssertEqual(app.staticTexts["category.count.roots"].label, "一级分类：7")
        XCTAssertEqual(selectedRoot(app), 800_001)
    }

    /// R-CATEGORY-01-01 long-list dynamic case: after selecting the last root
    /// the adjacent previous root's right group is just above the viewport and
    /// likely still realized. Tapping it must scroll the right target back to
    /// the top, not only move the highlight. This is also the scrolled-list
    /// background/selection case for the left rail.
    @MainActor func testLongListLastToPreviousRootScrollsRight() {
        let app = launch(categoryFixture: "many")
        openCategory(app)
        XCTAssertTrue(app.buttons["category.root.900001"].waitForExistence(timeout: 15))

        let left = app.scrollViews["category.left.scroll"]
        XCTAssertTrue(left.exists)
        let last = app.buttons["category.root.900015"]
        var tries = 0
        while !last.isHittable && tries < 6 {
            left.swipeUp()
            tries += 1
        }
        XCTAssertTrue(last.isHittable)
        last.tap()
        XCTAssertTrue(wait({ selectedRoot(app) == 900_015 }, timeout: 6))

        let previous = app.buttons["category.root.900014"]
        XCTAssertTrue(previous.isHittable)
        previous.tap()
        XCTAssertTrue(wait({ selectedRoot(app) == 900_014 }, timeout: 6))
        let scroll = app.scrollViews["category.right.scroll"]
        let title = app.staticTexts["category.group.900014.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(
            wait({ abs(title.frame.minY - scroll.frame.minY) <= 24 }, timeout: 5),
            "last->previous root must scroll the right target back to the top")
        attach(app, name: "category-many-previous-selected")
    }

    @MainActor func testEmptyState() {
        let app = launch(categoryFixture: "empty")
        openCategory(app)
        XCTAssertTrue(app.staticTexts["category.empty"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["category.retry"].exists)
    }

    @MainActor func testErrorRetryState() {
        let app = launch(categoryFixture: "retry")
        openCategory(app)
        XCTAssertTrue(app.staticTexts["category.error"].waitForExistence(timeout: 15))
        attach(app, name: "category-error")
        XCTAssertTrue(app.staticTexts["category.error.detail"].exists)
        let retry = app.buttons["category.retry"]
        XCTAssertTrue(retry.exists)
        retry.tap()
        XCTAssertTrue(app.buttons["category.root.800001"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["category.root.800001"].isSelected)
    }

    @MainActor func testLoadingState() {
        let app = launch(categoryFixture: "pending")
        openCategory(app)
        XCTAssertTrue(app.staticTexts["category.loading.message"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["category.empty"].exists)
    }
}
