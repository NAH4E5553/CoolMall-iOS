import MallCore
import Observation

/// Page state for the HOME-01 minimal read UI. The Scene/home-root view
/// identity owns this model; SwiftUI's task owns the await call.
///
/// Request validity: `generation` bumps on every accepted read and on every
/// visibility loss, so a stale success/error/cancellation can never overwrite
/// or clear a newer request (STATE-02/03). Retained ready/empty/failed states
/// survive tab switches with no implicit re-read; an unfinished first read
/// returns to idle and re-reads once when visible again.
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

    init(home: any HomeLoading) {
        self.home = home
    }

    /// Driven by `.task(id: isActive)`: SwiftUI cancels the previous task when
    /// the id changes, which also cancels the in-flight request.
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
            guard request == generation, !Task.isCancelled else { return }
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
            guard request == generation else { return }
            state = retainedState ?? .idle
        } catch {
            guard request == generation, !Task.isCancelled else { return }
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
