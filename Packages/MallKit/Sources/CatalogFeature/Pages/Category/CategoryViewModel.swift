import Foundation
import MallCore
import Observation

/// Page model for the category tab. Owns the committed snapshot, the selected
/// root and the read generation; the single SwiftUI `.task(id:)` awaits every
/// accepted read, so leaving the tab cancels the request and a late value/error
/// can never replace a newer read or a retained page state.
///
/// State contract: idle -> loading -> ready/empty/failed. A visibility loss
/// during loading restores the retained state (ready/empty/failed, else idle)
/// and invalidates the in-flight generation. Returning to the tab does not
/// re-read a retained result; an unfinished first read re-reads once. Retry is
/// accepted only from failed/empty (loading rejects a second retry) and is
/// driven by `readTicket`, which is part of the view task key.
///
/// Selection contract: the left rail selects by real root id (the reference
/// screen stores an index; ids are equivalent for this read-only scope and
/// survive payload reordering). A left tap bumps `scrollRequest` so the right
/// list scrolls to that group; right scrolling reports the first visible group
/// and changes the selection WITHOUT a scroll request. While a programmatic
/// scroll is pending, intermediate scroll observations are ignored — that is
/// the loop guard between the two directions.
@MainActor @Observable
final class CategoryViewModel {
    enum State: Equatable {
        case idle
        case loading
        case ready(CategorySnapshot)
        case empty
        case failed(CategoryLoadFailure)
    }

    struct ScrollRequest: Equatable {
        let token: UInt64
        let rootID: Int64
    }

    private(set) var state: State = .idle
    private(set) var selectedRootID: Int64?
    /// Set only by a left tap; read by the right list to perform one scroll.
    private(set) var scrollRequest: ScrollRequest?
    /// Part of the view task key: a retry bumps it, replacing the cancelled read.
    private(set) var readTicket: UInt64 = 0

    private let categories: any CategoryLoading
    private var generation = 0
    private var retainedState: State = .idle
    private var isActive = true
    private var startedOnce = false
    private var startedTicket: UInt64 = 0
    private var scrollToken: UInt64 = 0
    private var awaitingScrollTarget: Int64?

    init(categories: any CategoryLoading) {
        self.categories = categories
    }

    /// Synchronous visibility input from the entry's `onChange`. The SwiftUI
    /// `.task(id:)` may not run its replacement while a TabView child is
    /// offscreen, and an in-flight service that ignores caller cancellation
    /// would then commit; invalidating the generation HERE, before any await,
    /// guarantees the leaving read is stale even if its task is not cancelled.
    /// Returning only flips activity; the visible `.task` performs the drive.
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        guard !active else { return }
        generation += 1
        clearAwaitingScroll()
        if case .loading = state { state = retainedState }
    }

    /// Single drive entry for the view's `.task(id:)`. `active == false` is the
    /// visibility-loss path: invalidate the in-flight generation and restore
    /// the retained state; returning replays only the visibility path unless
    /// the previous read never committed (idle).
    func drive(active: Bool, ticket: UInt64) async {
        if isActive != active {
            setActive(active)
        }
        guard active else {
            return
        }
        if !startedOnce || ticket != startedTicket {
            startedOnce = true
            startedTicket = ticket
            await load()
            return
        }
        if case .idle = state {
            await load()
        }
    }

    /// Error/empty recovery. Accepted only when not loading; the ticket change
    /// restarts the view task, so the caller never owns a second I/O driver.
    func requestRetry() {
        switch state {
        case .failed, .empty:
            retainedState = state
            state = .loading
            readTicket &+= 1
        case .idle, .loading, .ready:
            break
        }
    }

    /// Left-rail tap. Selecting the already selected root is a no-op (the
    /// reference selected row is not actionable). A real change records the
    /// scroll intent consumed by the right list.
    func selectRoot(_ id: Int64) {
        guard case .ready(let snapshot) = state, snapshot.contains(rootID: id) else { return }
        guard selectedRootID != id else { return }
        selectedRootID = id
        awaitingScrollTarget = id
        scrollToken &+= 1
        scrollRequest = ScrollRequest(token: scrollToken, rootID: id)
    }

    /// Right-list scroll observation. While a left-tap scroll is pending, only
    /// the target observation completes it; intermediate groups are ignored and
    /// cannot bounce the selection or re-trigger scrolling.
    func selectFromScroll(_ id: Int64) {
        guard case .ready(let snapshot) = state, snapshot.contains(rootID: id) else { return }
        if let awaiting = awaitingScrollTarget {
            if id == awaiting { clearAwaitingScroll() }
            return
        }
        guard selectedRootID != id else { return }
        selectedRootID = id
    }

    /// A real user drag interrupts a programmatic scroll: stop suppressing
    /// observations so the next visible group can drive the selection.
    func userInterruptedProgrammaticScroll() {
        clearAwaitingScroll()
    }

    private func clearAwaitingScroll() {
        awaitingScrollTarget = nil
    }

    /// Page removal/teardown: invalidate the current generation so a late
    /// service completion cannot commit, and restore the retained state.
    func pageTeardown() {
        isActive = false
        generation += 1
        clearAwaitingScroll()
        if case .loading = state { state = retainedState }
    }

    private func load() async {
        generation += 1
        let request = generation
        state = .loading
        do {
            let values = try await categories.loadCategories()
            guard request == generation, isActive, !Task.isCancelled else {
                settleCancelled(request)
                return
            }
            commit(CategorySnapshot.build(from: values))
        } catch is CancellationError {
            settleCancelled(request)
        } catch {
            guard request == generation, isActive, !Task.isCancelled else {
                settleCancelled(request)
                return
            }
            let failure = error as? CategoryLoadFailure ?? .networkUnavailable
            state = .failed(failure)
            retainedState = .failed(failure)
        }
    }

    /// Only the request's own generation may restore state. A stale completion
    /// never clears a newer loading state or overwrites a newer result.
    private func settleCancelled(_ request: Int) {
        guard request == generation else { return }
        state = retainedState
    }

    private func commit(_ snapshot: CategorySnapshot) {
        clearAwaitingScroll()
        if snapshot.isEmpty {
            state = .empty
            retainedState = .empty
            selectedRootID = nil
            return
        }
        if let selectedRootID, snapshot.contains(rootID: selectedRootID) {
            // Keep the user's selection across a successful retry.
        } else {
            selectedRootID = snapshot.groups.first?.root.id
        }
        state = .ready(snapshot)
        retainedState = .ready(snapshot)
    }
}
