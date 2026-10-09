import MallCore
import Observation

/// Page state for the HOME-01 minimal read UI. The Scene/home-root view
/// identity owns this model; SwiftUI's task owns the await call.
///
/// Request validity: `generation` bumps on every accepted read and on every
/// visibility loss, so a stale success/error/cancellation can never overwrite
/// or clear a newer request (STATE-02/03). Retained ready/empty/failed states
/// survive tab switches with no implicit re-read; an unfinished first read
/// returns to idle and re-reads once when visible again. A still-current
/// request that gets cancelled — including a service that ignores
/// cancellation and returns a value or a plain error — falls back to the
/// retained state instead of stranding the page in loading (R-HOME-01-01).
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

    init(home: any HomeLoading) {
        self.home = home
    }

    /// Single drive entry for the view's one `.task(id:)`: the key covers both
    /// visibility and the retry trigger, so ANY key change cancels the
    /// in-flight await — the first read and a user retry are cancelled alike
    /// by an explicit visibility loss, never only by onDisappear
    /// (R-HOME-01-01). A retry token is consumed exactly once: later
    /// visibility drives replay the visibility path only and never
    /// auto-retry a retained failed/empty.
    func drive(active: Bool, retryToken: Int) async {
        if retryToken != lastConsumedRetryToken {
            lastConsumedRetryToken = retryToken
            if active {
                await retry()
            } else {
                suspend()
            }
            return
        }
        await handleVisibility(active)
    }

    /// Visibility half of the drive contract. `active` triggers the first
    /// read from idle; `false` revokes the generation and restores the
    /// retained state (or idle).
    func handleVisibility(_ active: Bool) async {
        if active {
            await loadIfNeeded()
        } else {
            suspend()
        }
    }

    /// User retry — allowed only from failed/empty; loading accepts no second
    /// action, ready has no refresh in HOME-01.
    func retry() async {
        switch state {
        case .failed, .empty: await load()
        case .idle, .loading, .ready: break
        }
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

    /// Visibility lost: invalidate the in-flight generation and restore the
    /// retained state (or idle); the cancelled task's stale commit is
    /// rejected by the generation guard.
    private func suspend() {
        generation += 1
        if case .loading = state {
            state = retainedState ?? .idle
        }
    }
}
