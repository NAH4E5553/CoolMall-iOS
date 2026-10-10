import MallCore
import Observation

/// Page state for the HOME-01 minimal read UI plus the HOME-02-R1 re-tap
/// refresh. The Scene/home-root view identity owns this model; SwiftUI's task
/// owns every await call.
///
/// Request validity: `generation` bumps on every accepted read and on every
/// visibility loss, so a stale success/error/cancellation can never overwrite
/// or clear a newer request (STATE-02/03). Retained ready/empty/failed states
/// survive tab switches with no implicit re-read; an unfinished first read
/// returns to idle and re-reads once when visible again. A still-current
/// request that gets cancelled — including a service that ignores
/// cancellation and returns a value or a plain error — falls back to the
/// retained state instead of stranding the page in loading (R-HOME-01-01).
///
/// HOME-02-R1 refresh (H0 v0.3/PRD-019): a re-tap refresh keeps the committed
/// snapshot visible behind a small indicator; success replaces the snapshot
/// wholesale, failure keeps the old content behind a retryable hint, and a
/// busy model (first load or active refresh) accepts no second request. The
/// raw re-tap counter never drives task keys — only the model-accepted
/// `refreshTicket` does, so ignored re-taps cannot cancel an active request.
@MainActor @Observable
final class HomeViewModel {
    enum State: Equatable {
        case idle
        case loading
        case ready(HomeSnapshot)
        case empty(HomeSnapshot)
        case failed(HomeLoadFailure)
    }

    private(set) var state: State = .idle
    private let home: any HomeLoading
    private var generation = 0
    private var retainedState: State?
    private var lastConsumedRetryToken = 0

    // HOME-02-R1 refresh state (internal projections only).
    private(set) var isRefreshing = false
    private(set) var refreshFailedHint = false
    /// Monotonic ticket bumped whenever a refresh intent is ACCEPTED; the
    /// entry mirrors it into its single drive task key.
    private(set) var refreshTicket: UInt64 = 0
    private var acceptedRefreshPending = false
    private var lastHandledReTapToken: UInt64 = 0

    init(home: any HomeLoading) {
        self.home = home
    }

    /// Single drive entry for the view's one `.task(id:)`. The key covers
    /// visibility, the original retry trigger and the model-ACCEPTED refresh
    /// ticket, so ANY key change cancels the in-flight await — the first
    /// read and a refresh are cancelled alike by an explicit visibility loss,
    /// never only by onDisappear. Losing visibility is routed FIRST: an
    /// accepted-but-unstarted refresh is dropped (no hidden off-page request)
    /// and the indicator closes. A retry token is consumed exactly once;
    /// rejected re-taps never change the key.
    func drive(active: Bool, retryToken: Int) async {
        // R-HOME-02-R1-01: losing visibility always wins — an accepted but
        // not-yet-started refresh is dropped here (suspend clears it), so an
        // off-page drive can never issue a hidden request.
        guard active else {
            suspend()
            return
        }
        if acceptedRefreshPending {
            await runAcceptedRefresh()
            return
        }
        if retryToken != lastConsumedRetryToken {
            lastConsumedRetryToken = retryToken
            await retry()
            return
        }
        await handleVisibility(active)
    }

    /// Visibility half of the drive contract. `active` triggers the first
    /// read from idle; `false` revokes the generation, closes the refresh
    /// indicator and clears an un-run accepted refresh (returning to the page
    /// never re-fires it), restoring the retained state (or idle).
    func handleVisibility(_ active: Bool) async {
        if active {
            await loadIfNeeded()
        } else {
            suspend()
        }
    }

    /// Original user retry — allowed only from failed/empty; loading accepts
    /// no second action, ready keeps no refresh entry in HOME-01 semantics.
    func retry() async {
        switch state {
        case .failed, .empty: await load()
        case .idle, .loading, .ready: break
        }
    }

    /// Synchronous re-tap entry from the App's read-only event counter.
    /// Deduplicates by token; rejects while a first load or a refresh is in
    /// flight (busy ⇒ scroll-to-top only, no stacking/restart/queueing); an
    /// accepted intent clears the previous failure hint and bumps the ticket
    /// the drive key mirrors.
    func requestRefresh(_ token: UInt64) {
        guard token != lastHandledReTapToken else { return }
        lastHandledReTapToken = token
        switch state {
        case .ready, .empty, .failed:
            break
        case .idle, .loading:
            return
        }
        // R-HOME-02-R1-02: acceptance itself reserves the busy slot — a
        // second token in the accepted-but-not-started window is rejected
        // (ticket unchanged, nothing queued or restarted).
        guard !isRefreshing, !acceptedRefreshPending else { return }
        refreshFailedHint = false
        acceptedRefreshPending = true
        refreshTicket &+= 1
    }

    /// Retry entry for the refresh-failure hint row — a NEW refresh action,
    /// distinct from the original failed/empty retry; still the same model.
    func requestRetryRefresh() {
        guard refreshFailedHint else { return }
        switch state {
        case .ready, .empty: break
        case .idle, .loading, .failed: return
        }
        // Same busy/acceptance-slot contract as re-tap refreshes.
        guard !isRefreshing, !acceptedRefreshPending else { return }
        refreshFailedHint = false
        acceptedRefreshPending = true
        refreshTicket &+= 1
    }

    private func runAcceptedRefresh() async {
        guard acceptedRefreshPending else { return }
        acceptedRefreshPending = false
        await performRefresh()
    }

    private func loadIfNeeded() async {
        switch state {
        case .idle: await load()
        case .loading, .ready, .empty, .failed: break
        }
    }

    private func load() async {
        generation += 1
        let request = generation
        state = .loading
        do {
            let snapshot = try await home.loadHome()
            guard request == generation, !Task.isCancelled else {
                // Superseded (suspend or a newer request took over): leave the
                // newer state untouched. Still-current but cancelled — even a
                // service that ignored cancellation and returned a value —
                // falls back to the retained state, never strands loading.
                if request == generation {
                    state = retainedState ?? .idle
                }
                return
            }
            commitDisplayState(for: snapshot)
        } catch is CancellationError {
            // A cancelled read leaves the latest committed state in place; an
            // unfinished first read falls back to idle.
            if request == generation {
                state = retainedState ?? .idle
            }
        } catch {
            guard request == generation, !Task.isCancelled else {
                // A plain error arriving after cancellation is a cancellation
                // outcome: restore the retained state, do not surface it as a
                // fresh failure.
                if request == generation {
                    state = retainedState ?? .idle
                }
                return
            }
            let next = State.failed(error as? HomeLoadFailure ?? .networkUnavailable)
            state = next
            retainedState = next
        }
    }

    /// HOME-02-R1 refresh. With committed content (ready/empty) the snapshot
    /// stays visible behind `isRefreshing`; without any committed result a
    /// re-tap on the full-page failure simply reloads through the H0 first
    /// -load UI. The old task can only settle its own generation: every flag
    /// cleanup is generation-guarded so a superseded completion never clears
    /// a newer refresh's state.
    private func performRefresh() async {
        generation += 1
        let request = generation
        let keepsOldContent: Bool
        switch state {
        case .ready, .empty:
            keepsOldContent = true
            isRefreshing = true
        case .failed:
            keepsOldContent = false
            state = .loading
        case .idle, .loading:
            return
        }
        do {
            let snapshot = try await home.loadHome()
            guard request == generation, !Task.isCancelled else {
                settleCancelledRefresh(request: request, keepsOldContent: keepsOldContent)
                return
            }
            commitDisplayState(for: snapshot)
            isRefreshing = false
        } catch is CancellationError {
            // Cancelled: close the indicator; a cancellation is never shown
            // as a failure, and a cancelled reload restores retained state.
            settleCancelledRefresh(request: request, keepsOldContent: keepsOldContent)
        } catch {
            guard request == generation, !Task.isCancelled else {
                settleCancelledRefresh(request: request, keepsOldContent: keepsOldContent)
                return
            }
            isRefreshing = false
            if keepsOldContent {
                // Old ready/empty stays; only the hint asks for a retry.
                refreshFailedHint = true
            } else {
                let next = State.failed(error as? HomeLoadFailure ?? .networkUnavailable)
                state = next
                retainedState = next
            }
        }
    }

    /// Terminal settling for a cancelled refresh outcome — including a
    /// service that ignored cancellation and returned a value or a plain
    /// error. Only the request's OWN generation is settled (a superseded
    /// completion must not touch a newer refresh's state or flags); a
    /// reload-style refresh restores the retained state so the page can
    /// never stay stranded in loading.
    private func settleCancelledRefresh(request: Int, keepsOldContent: Bool) {
        guard request == generation else { return }
        isRefreshing = false
        if !keepsOldContent {
            state = retainedState ?? .idle
        }
    }

    private func commitDisplayState(for snapshot: HomeSnapshot) {
        let displayEmpty =
            snapshot.banners.isEmpty
            && snapshot.categories.isEmpty
            && snapshot.featured.isEmpty
            && snapshot.recommendations.isEmpty
            && snapshot.goods.isEmpty
            && snapshot.coupons.isEmpty
        let next: State = displayEmpty ? .empty(snapshot) : .ready(snapshot)
        state = next
        retainedState = next
    }

    /// Visibility lost: invalidate the in-flight generation, drop an un-run
    /// accepted refresh and close the indicator (returning never re-fires
    /// it), and restore the retained state (or idle); the cancelled task's
    /// stale commit is rejected by the generation guard.
    private func suspend() {
        generation += 1
        acceptedRefreshPending = false
        isRefreshing = false
        if case .loading = state {
            state = retainedState ?? .idle
        }
    }
}
