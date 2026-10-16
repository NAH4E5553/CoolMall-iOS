import Foundation
import MallCore
@testable import CatalogFeature
import Testing

struct HomeBannerSelectionTests {
    @Test func initialAndReorderedSelectionUsesID() {
        var selection = HomeBannerSelection()
        selection.reconcile(with: [1, 2, 3])
        #expect(selection.selectedID == 1)
        selection.reconcile(with: [1, 2, 3])
        selection.select(2)
        // Effective selection is safe even before onChange reconciliation.
        #expect(selection.currentID(in: [3, 2, 1]) == 2)
        selection.reconcile(with: [3, 2, 1])
        #expect(selection.selectedID == 2)
    }

    @Test func deletionEmptyAndReturnUseNewFirst() {
        var selection = HomeBannerSelection()
        selection.reconcile(with: [1, 2, 3])
        selection.select(2)
        #expect(selection.currentID(in: [3, 1]) == 3)
        selection.reconcile(with: [3, 1])
        #expect(selection.selectedID == 3)
        selection.reconcile(with: [])
        #expect(selection.selectedID == nil)
        selection.reconcile(with: [1])
        #expect(selection.selectedID == 1)
    }

    @Test func changedURLDoesNotChangeSelectedIdentity() {
        var selection = HomeBannerSelection()
        let old = HomeBanner(
            id: 2, description: "B", imageURL: URL(string: "https://test.invalid/a"))
        let new = HomeBanner(
            id: 2, description: "B", imageURL: URL(string: "https://test.invalid/b"))
        selection.reconcile(with: [1, old.id, 3])
        selection.select(old.id)
        selection.reconcile(with: [3, new.id, 1])
        #expect(selection.selectedID == new.id)
        #expect(old.imageURL != new.imageURL)
    }

    @Test func delayedMissingIDCannotReselectRemovedPage() {
        var selection = HomeBannerSelection()
        selection.reconcile(with: [1, 2, 3])
        selection.select(2)
        selection.reconcile(with: [3, 1])
        selection.select(2)
        #expect(selection.selectedID == 3)
        selection.reconcile(with: [])
        selection.select(3)
        #expect(selection.selectedID == nil)
    }

    @Test func boundariesNeverWrapAndSingleHasNoNeighbor() {
        var selection = HomeBannerSelection()
        selection.reconcile(with: [1, 2, 3])
        #expect(selection.adjacentID(offset: -1, in: [1, 2, 3]) == nil)
        #expect(selection.adjacentID(offset: 1, in: [1, 2, 3]) == 2)
        selection.reconcile(with: [1, 2, 3])
        selection.select(3)
        #expect(selection.adjacentID(offset: 1, in: [1, 2, 3]) == nil)
        #expect(selection.adjacentID(offset: -1, in: [1, 2, 3]) == 2)
        selection.reconcile(with: [8])
        #expect(selection.adjacentID(offset: -1, in: [8]) == nil)
        #expect(selection.adjacentID(offset: 1, in: [8]) == nil)
        #expect(selection.adjacentID(offset: 1, in: []) == nil)
    }
}
