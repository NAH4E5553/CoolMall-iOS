import XCTest

/// Only App composition/navigation is new here. The accepted category page and
/// detail/reviews state machines keep their original tests and known failures.
final class CatalogIntegrationTests: XCTestCase {
    @MainActor func testCategorySelectionSurvivesDetailAndReviewRoundTrip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-home-fixture", "valid", "--ui-banner-manual",
            "--ui-category-fixture", "tab-return",
            "--ui-product-detail-fixture", "valid",
            "--ui-product-reviews-fixture", "valid",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 10))
        app.tabBars.buttons["分类"].tap()
        let selected = app.buttons["category.root.800002"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        selected.tap()
        XCTAssertTrue(selected.isSelected)
        XCTAssertEqual(app.staticTexts["category.count.roots"].label, "一级分类：7")
        let category = XCTAttachment(screenshot: app.screenshot())
        category.name = "integrated-category"; category.lifetime = .keepAlways; add(category)

        app.tabBars.buttons["首页"].tap()
        let product = app.buttons["home.flashSale.830001.card"]
        for _ in 0..<5 { if product.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(product.isHittable); product.tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.scrollViews["detail.scroll"].value as? String, "商品ID：830001")
        XCTAssertFalse(app.tabBars.buttons["分类"].exists)

        let all = app.buttons["detail.reviews.all"]
        let top = app.buttons["detail.back"].frame.maxY + 8
        let bottom = app.buttons["客服"].frame.minY - 8
        let center = (top + bottom) / 2
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = app.frame.midX
        for _ in 0..<6 {
            let frame = all.frame
            if all.isHittable && frame.minY >= top && frame.maxY <= bottom { break }
            let delta = frame.midY - center
            let start = delta >= 0 ? bottom - 16 : top + 16
            let end = min(bottom - 16, max(top + 16, start - delta))
            origin.withOffset(CGVector(dx: x, dy: start)).press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: x, dy: end)))
        }
        XCTAssertTrue(all.isHittable)
        XCTAssertGreaterThanOrEqual(all.frame.minY, top)
        XCTAssertLessThanOrEqual(all.frame.maxY, bottom)
        all.tap()
        XCTAssertTrue(app.navigationBars["商品评价"].waitForExistence(timeout: 5))
        let list = app.descendants(matching: .any)["reviews.list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertEqual(list.value as? String, "商品ID：830001")
        XCTAssertTrue(app.staticTexts["121****50"].exists)
        XCTAssertFalse(app.tabBars.buttons["分类"].exists)
        let reviews = XCTAttachment(screenshot: app.screenshot())
        reviews.name = "integrated-reviews"; reviews.lifetime = .keepAlways; add(reviews)
        // No pull here: R-REVIEWS-01 remains an independent unresolved failure.
        app.buttons["reviews.back"].tap()
        XCTAssertTrue(app.staticTexts["detail.loaded"].waitForExistence(timeout: 5))
        app.buttons["detail.back"].tap()
        XCTAssertTrue(app.staticTexts["home.loaded"].waitForExistence(timeout: 5))
        app.tabBars.buttons["分类"].tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.isSelected)
        // This fixture returns only 3 roots if composition re-creates/re-reads.
        XCTAssertEqual(app.staticTexts["category.count.roots"].label, "一级分类：7")
        XCTAssertFalse(app.staticTexts["category.pending"].exists)
    }
}
