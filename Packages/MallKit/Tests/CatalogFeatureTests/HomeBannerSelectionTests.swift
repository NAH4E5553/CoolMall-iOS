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

struct HomeBannerAutoplayTests {
    @Test func earlyAndSupersededWakesCannotAdvance() {
        let now = ContinuousClock().now
        var playback = HomeBannerAutoplay()
        let old = playback.restart(at: now, eligible: true)
        // Hoisted: #expect's expansion captures an immutable copy, so the
        // mutating consume() must run outside the macro expression.
        let early = playback.consume(old, at: now.advanced(by: .seconds(4)))
        #expect(!early)
        let replacement = playback.restart(at: now.advanced(by: .seconds(4)), eligible: true)
        let superseded = playback.consume(old, at: now.advanced(by: .seconds(5)))
        #expect(!superseded)
        let stillEarly = playback.consume(replacement, at: now.advanced(by: .seconds(8)))
        #expect(!stillEarly)
        let onTime = playback.consume(replacement, at: now.advanced(by: .seconds(9)))
        #expect(onTime)
        let repeatWake = playback.consume(replacement, at: now.advanced(by: .seconds(10)))
        #expect(!repeatWake)
    }

    @Test func pauseCancelsAndResumeDoesNotCatchUp() {
        let now = ContinuousClock().now
        var playback = HomeBannerAutoplay()
        let old = playback.restart(at: now, eligible: true)
        let paused = playback.restart(at: now.advanced(by: .seconds(2)), eligible: false)
        #expect(playback.deadline == nil)
        let lateOld = playback.consume(old, at: now.advanced(by: .seconds(60)))
        #expect(!lateOld)
        let latePaused = playback.consume(paused, at: now.advanced(by: .seconds(60)))
        #expect(!latePaused)
        let resumed = playback.restart(at: now.advanced(by: .seconds(60)), eligible: true)
        let catchUp = playback.consume(resumed, at: now.advanced(by: .seconds(64)))
        #expect(!catchUp)
        let freshDeadline = playback.consume(resumed, at: now.advanced(by: .seconds(65)))
        #expect(freshDeadline)
    }
}

struct HomeBannerAutoplayGateTests {
    private func gate(
        bannerCount: Int = 3,
        allowsAutoplay: Bool = true,
        isHomeActive: Bool = true,
        isSceneActive: Bool = true,
        reducesMotion: Bool = false,
        isVoiceOverRunning: Bool = false,
        isDragging: Bool = false,
        bannerFrame: CGRect = CGRect(x: 0, y: 100, width: 390, height: 195),
        viewport: CGRect = CGRect(x: 0, y: 0, width: 390, height: 800)
    ) -> HomeBannerAutoplayGate {
        HomeBannerAutoplayGate(
            bannerCount: bannerCount,
            allowsAutoplay: allowsAutoplay,
            isHomeActive: isHomeActive,
            isSceneActive: isSceneActive,
            reducesMotion: reducesMotion,
            isVoiceOverRunning: isVoiceOverRunning,
            isDragging: isDragging,
            bannerFrame: bannerFrame,
            viewport: viewport)
    }

    @Test func multipleVisibleBannersAreEligible() {
        #expect(gate().isEligible)
    }

    @Test func emptyOrSingleBannerNeverStartsTheTimer() {
        #expect(!gate(bannerCount: 0).isEligible)
        #expect(!gate(bannerCount: 1).isEligible)
        #expect(gate(bannerCount: 2).isEligible)
    }

    @Test func manualGateInactiveHomeOrScenePauses() {
        #expect(!gate(allowsAutoplay: false).isEligible)
        #expect(!gate(isHomeActive: false).isEligible)
        #expect(!gate(isSceneActive: false).isEligible)
    }

    @Test func assistiveMotionSettingsDisableAutoplay() {
        #expect(!gate(reducesMotion: true).isEligible)
        #expect(!gate(isVoiceOverRunning: true).isEligible)
    }

    @Test func dragPausesAndOffscreenBannerPauses() {
        #expect(!gate(isDragging: true).isEligible)
        #expect(!gate(bannerFrame: CGRect(x: 0, y: -300, width: 390, height: 195)).isEligible)
        #expect(!gate(bannerFrame: CGRect(x: 0, y: 1200, width: 390, height: 195)).isEligible)
        #expect(gate(bannerFrame: CGRect(x: 0, y: -100, width: 390, height: 195)).isEligible)
    }
}
