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

        // F-CATEGORY-05 navigation INTENT only: tapping the real direct-child id
        // shows the explicit unavailable feedback; no list page is faked.
        attach(app, name: "category-valid-layout")

        first.tap()
        XCTAssertTrue(app.staticTexts["category.unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            wait({ !app.staticTexts["category.unavailable"].exists }, timeout: 4),
            "the unavailable feedback clears itself")

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
    }

    @MainActor func testEmptyErrorRetryAndLoadingStates() {
        let emptyApp = launch(categoryFixture: "empty")
        openCategory(emptyApp)
        XCTAssertTrue(emptyApp.staticTexts["category.empty"].waitForExistence(timeout: 15))
        XCTAssertFalse(emptyApp.buttons["category.retry"].exists)
        emptyApp.terminate()

        let retryApp = launch(categoryFixture: "retry")
        openCategory(retryApp)
        XCTAssertTrue(retryApp.staticTexts["category.error"].waitForExistence(timeout: 15))
        XCTAssertTrue(retryApp.staticTexts["category.error.detail"].exists)
        let retry = retryApp.buttons["category.retry"]
        XCTAssertTrue(retry.exists)
        retry.tap()
        XCTAssertTrue(retryApp.buttons["category.root.800001"].waitForExistence(timeout: 15))
        XCTAssertTrue(retryApp.buttons["category.root.800001"].isSelected)
        retryApp.terminate()

        let loadingApp = launch(categoryFixture: "pending")
        openCategory(loadingApp)
        XCTAssertTrue(
            loadingApp.staticTexts["category.loading.message"].waitForExistence(timeout: 15))
        XCTAssertFalse(loadingApp.staticTexts["category.empty"].exists)
        loadingApp.terminate()
    }
}
