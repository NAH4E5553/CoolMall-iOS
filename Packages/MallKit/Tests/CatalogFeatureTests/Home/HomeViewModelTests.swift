import Foundation
import MallCore
@testable import CatalogFeature
import Testing

/// AT-HOME-01-06…09: page-state machine over a scripted service — retries,
/// retention, visibility suspension, stale-result rejection and cancellation.
/// Sequences are gate/continuation controlled; no sleep-based ordering.
@MainActor
struct HomeViewModelTests {
    @MainActor
    final class ScriptedService: HomeLoading {
        enum Step {
            case value(HomeSnapshot)
            case failure(HomeLoadFailure)
            case gate
            case never
        }

        private var steps: [Step]
        private(set) var calls = 0
        private var gated: [CheckedContinuation<Result<HomeSnapshot, Error>, Never>] = []

        init(steps: [Step]) {
            self.steps = steps
        }

        func loadHome() async throws -> HomeSnapshot {
            calls += 1
            let step = steps.isEmpty ? .never : steps.removeFirst()
            switch step {
            case .value(let snapshot): return snapshot
            case .failure(let failure): throw failure
            case .gate:
                return try await withCheckedContinuation { continuation in
                    gated.append(continuation)
                }.get()
            case .never:
                // Suspends until the surrounding task is cancelled; throws
                // CancellationError instead of returning.
                while true {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            }
        }

        func release(_ result: Result<HomeSnapshot, Error>) {
            guard !gated.isEmpty else { return }
            gated.removeFirst().resume(returning: result)
        }

        /// Resumes the MOST RECENTLY registered gated call first — lets a
        /// newer request B complete before an older suspended A.
        func releaseLatest(_ result: Result<HomeSnapshot, Error>) {
            guard !gated.isEmpty else { return }
            gated.removeLast().resume(returning: result)
        }
    }

    static func snapshot(goodsID: Int64) -> HomeSnapshot {
        HomeSnapshot(
            banners: [HomeBanner(id: goodsID, description: "夹具", imageURL: nil)],
            categories: [], allCategories: [],
            featured: [], recommendations: [],
            goods: [
                HomeProductSummary(
                    id: goodsID, title: "商品\(goodsID)", subtitle: nil, imageURL: nil,
                    priceYuan: Decimal(1))
            ],
            coupons: []
        )
    }

    static let emptySnapshot = HomeSnapshot(
        banners: [], categories: [],
        allCategories: [HomeCategory(id: 800_001, name: "手机", parentID: nil, imageURL: nil)],
        featured: [], recommendations: [], goods: [], coupons: []
    )

    /// Yields until the condition holds on the main actor; bounded so a bug
    /// fails the test instead of hanging it.
    private func waitUntil(_ condition: () -> Bool) async {
        var spins = 0
        while !condition() {
            spins += 1
            if spins > 200_000 {
                Issue.record("condition not met before spin budget")
                return
            }
            await Task.yield()
        }
    }

    // MARK: AT-06 success / empty / retry

    @Test func firstLoadSuccessCommitsReady() async {
        let service = ScriptedService(steps: [.value(Self.snapshot(goodsID: 1))])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        #expect(service.calls == 1)
        guard case .ready(let snapshot) = viewModel.state else {
            Issue.record("expected ready, got \(viewModel.state)")
            return
        }
        #expect(snapshot.goods.first?.id == 1)
    }

    @Test func sixEmptyDisplayArraysCommitEmptyEvenWithAuxiliaryCategories() async {
        let service = ScriptedService(steps: [.value(Self.emptySnapshot)])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .empty(let snapshot) = viewModel.state else {
            Issue.record("expected empty, got \(viewModel.state)")
            return
        }
        #expect(snapshot.allCategories.count == 1)
    }

    @Test func failureThenSingleUserRetrySucceeds() async {
        let service = ScriptedService(steps: [
            .failure(.networkUnavailable), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .failed(.networkUnavailable) = viewModel.state else {
            Issue.record("expected failed")
            return
        }
        await viewModel.retry()
        #expect(service.calls == 2)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after retry")
            return
        }
    }

    @Test func validEmptyCanRetryAndReadyHasNoRefreshAction() async {
        let service = ScriptedService(steps: [
            .value(Self.emptySnapshot), .value(Self.snapshot(goodsID: 3)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .empty = viewModel.state else { return }
        await viewModel.retry()
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after empty retry")
            return
        }
        // Ready has no refresh in HOME-01: retry() must be a no-op here.
        await viewModel.retry()
        #expect(service.calls == 2)
    }

    @Test func loadingRejectsSecondRetry() async {
        let service = ScriptedService(steps: [.gate, .value(Self.snapshot(goodsID: 4))])
        let viewModel = HomeViewModel(home: service)
        let firstLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })
        await viewModel.retry()
        #expect(service.calls == 1)
        service.release(.success(Self.snapshot(goodsID: 4)))
        await firstLoad.value
        guard case .ready = viewModel.state else {
            Issue.record("expected ready")
            return
        }
    }

    // MARK: AT-07 visibility loss, cancel, re-read, retention

    @Test func visibilityLossSuspendsFirstReadToIdleAndReReadsOnceOnReturn() async {
        let service = ScriptedService(steps: [.gate, .value(Self.snapshot(goodsID: 6))])
        let viewModel = HomeViewModel(home: service)
        let firstLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })

        await viewModel.handleVisibility(false)
        #expect(viewModel.state == .idle)

        let secondLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 2 })
        // Late A completion must be discarded: its generation was revoked.
        service.release(.success(Self.snapshot(goodsID: 5)))
        await firstLoad.value
        await secondLoad.value
        guard case .ready(let snapshot) = viewModel.state else {
            Issue.record("expected ready after re-read")
            return
        }
        #expect(snapshot.goods.first?.id == 6)
    }

    @Test func lateFailureAfterSuspensionDoesNotDisturbNewRequest() async {
        let service = ScriptedService(steps: [.gate, .value(Self.snapshot(goodsID: 7))])
        let viewModel = HomeViewModel(home: service)
        let firstLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })
        await viewModel.handleVisibility(false)
        let secondLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 2 })
        service.release(.failure(HomeLoadFailure.timeout))
        await firstLoad.value
        await secondLoad.value
        guard case .ready = viewModel.state else {
            Issue.record("expected ready")
            return
        }
    }

    @Test func failedIsRetainedAcrossVisibilityWithoutAutoRetry() async {
        let service = ScriptedService(steps: [.failure(.timeout)])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        await viewModel.handleVisibility(false)
        await viewModel.handleVisibility(true)
        #expect(service.calls == 1)
        guard case .failed(.timeout) = viewModel.state else {
            Issue.record("expected failed retained")
            return
        }
    }

    @Test func readySnapshotIsRetainedWithoutImplicitReread() async {
        let snapshot = Self.snapshot(goodsID: 8)
        let service = ScriptedService(steps: [.value(snapshot)])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        for _ in 0..<2 {
            await viewModel.handleVisibility(false)
            await viewModel.handleVisibility(true)
        }
        #expect(service.calls == 1)
        #expect(viewModel.state == .ready(snapshot))
    }

    @Test func taskCancellationOfFirstReadReturnsToIdle() async {
        let service = ScriptedService(steps: [.never])
        let viewModel = HomeViewModel(home: service)
        let task = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })
        task.cancel()
        await task.value
        #expect(viewModel.state == .idle)
    }

    // MARK: AT-08 out-of-order after cancel

    @Test func cancelledThenFasterNewReadWinsOverStaleCompletions() async {
        // Both calls are gated; B (newer) is released first, then stale A.
        let service = ScriptedService(steps: [.gate, .gate])
        let viewModel = HomeViewModel(home: service)
        let firstLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })
        await viewModel.handleVisibility(false)
        let secondLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 2 })
        service.releaseLatest(.success(Self.snapshot(goodsID: 10)))
        await secondLoad.value
        guard case .ready(let committed) = viewModel.state else {
            Issue.record("expected ready from B")
            return
        }
        service.release(.success(Self.snapshot(goodsID: 9)))
        await firstLoad.value
        #expect(committed.goods.first?.id == 10)
        #expect(viewModel.state == .ready(committed))
    }

    @Test func retryCancelledMidFlightRestoresRetainedFailure() async {
        let service = ScriptedService(steps: [.failure(.timeout), .never])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .failed = viewModel.state else { return }
        let retryTask = Task { await viewModel.retry() }
        await waitUntil({ service.calls == 2 })
        retryTask.cancel()
        await retryTask.value
        guard case .failed(.timeout) = viewModel.state else {
            Issue.record("expected retained failure after cancelled retry")
            return
        }
    }

    // MARK: R-HOME-01-01 cancellation completion must not strand loading

    @Test func cancelledTaskReturningValueRestoresIdleThenRereadSucceeds() async {
        // The gated service ignores cancellation and returns a value anyway;
        // the still-current request must fall back to idle (was: stuck loading).
        let service = ScriptedService(steps: [.gate, .value(Self.snapshot(goodsID: 11))])
        let viewModel = HomeViewModel(home: service)
        let task = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })
        task.cancel()
        service.release(.success(Self.emptySnapshot))
        await task.value
        #expect(viewModel.state == .idle)
        await viewModel.handleVisibility(true)
        #expect(service.calls == 2)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after re-read following cancelled value")
            return
        }
    }

    @Test func cancelledTaskThrowingPlainErrorRestoresIdleNotFailed() async {
        let service = ScriptedService(steps: [.gate])
        let viewModel = HomeViewModel(home: service)
        let task = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })
        task.cancel()
        service.release(.failure(HomeLoadFailure.timeout))
        await task.value
        #expect(viewModel.state == .idle)
    }

    @Test func validEmptyCommitSurvivesLateFailureFromRevokedRequest() async {
        // B commits a valid empty; the older, revoked A then fails — empty must
        // stay untouched (no ordinary-error surfacing, no clearing).
        let service = ScriptedService(steps: [.gate, .gate])
        let viewModel = HomeViewModel(home: service)
        let firstLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })
        await viewModel.handleVisibility(false)
        let secondLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 2 })
        service.releaseLatest(.success(Self.emptySnapshot))
        await secondLoad.value
        guard case .empty = viewModel.state else {
            Issue.record("expected empty from B")
            return
        }
        service.release(.failure(HomeLoadFailure.httpStatus(500)))
        await firstLoad.value
        guard case .empty = viewModel.state else {
            Issue.record("late A failure must not disturb committed empty")
            return
        }
    }

    // MARK: R-HOME-01-01 drive: retry is visibility-cancelled, token consumed once

    @Test func driveCancelsInFlightRetryOnVisibilityLossWithoutAutoRetry() async {
        let service = ScriptedService(steps: [
            .failure(.timeout), .gate, .value(Self.snapshot(goodsID: 12)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.drive(active: true, retryToken: 0)
        guard case .failed(.timeout) = viewModel.state else {
            Issue.record("expected failed first read")
            return
        }
        // User retry while active: the drive task starts a hanging request.
        let retryTask = Task { await viewModel.drive(active: true, retryToken: 1) }
        await waitUntil({ service.calls == 2 })
        // Leaving the page: the single drive task is cancelled and restarted
        // with active=false — the in-flight retry is revoked and the retained
        // failure restored; its late success is discarded.
        retryTask.cancel()
        await viewModel.drive(active: false, retryToken: 1)
        service.release(.success(Self.snapshot(goodsID: 12)))
        await retryTask.value
        guard case .failed(.timeout) = viewModel.state else {
            Issue.record("expected retained failure after visibility-cancelled retry")
            return
        }
        // Returning to the tab replays only the visibility path: the retry
        // token was consumed, so there is no automatic retry.
        await viewModel.drive(active: true, retryToken: 1)
        #expect(service.calls == 2)
        guard case .failed(.timeout) = viewModel.state else {
            Issue.record("return must not auto-retry failed")
            return
        }
        // A NEW explicit retry (fresh token) succeeds.
        await viewModel.drive(active: true, retryToken: 2)
        #expect(service.calls == 3)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after new explicit retry")
            return
        }
    }

    // MARK: HOME-02-R1 re-tap refresh (H0 v0.3)

    @Test func reTapRefreshFromReadyReplacesSnapshotAndClearsFlags() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after first load")
            return
        }
        viewModel.requestRefresh(1)
        #expect(viewModel.refreshTicket == 1)
        await viewModel.drive(active: true, retryToken: 0)
        #expect(service.calls == 2)
        guard case .ready(let snapshot) = viewModel.state else {
            Issue.record("expected ready after refresh")
            return
        }
        #expect(snapshot.goods.first?.id == 2)
        #expect(!viewModel.isRefreshing)
        #expect(!viewModel.refreshFailedHint)
        // Same token is deduplicated: no second ticket, nothing pending.
        viewModel.requestRefresh(1)
        #expect(viewModel.refreshTicket == 1)
    }

    @Test func reTapRefreshFromEmptyCanProduceReady() async {
        let service = ScriptedService(steps: [
            .value(Self.emptySnapshot), .value(Self.snapshot(goodsID: 3)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .empty = viewModel.state else {
            Issue.record("expected empty after first load")
            return
        }
        viewModel.requestRefresh(1)
        await viewModel.drive(active: true, retryToken: 0)
        #expect(service.calls == 2)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after refreshing an empty snapshot")
            return
        }
    }

    @Test func refreshFailureKeepsOldContentHintAndRetryRefreshSucceeds() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 5)), .failure(.timeout),
            .value(Self.snapshot(goodsID: 6)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .ready(let committed) = viewModel.state else { return }
        viewModel.requestRefresh(1)
        await viewModel.drive(active: true, retryToken: 0)
        // Failure keeps the old snapshot visible plus the retryable hint.
        #expect(viewModel.state == .ready(committed))
        #expect(viewModel.refreshFailedHint)
        #expect(!viewModel.isRefreshing)
        viewModel.requestRetryRefresh()
        #expect(viewModel.refreshTicket == 2)
        await viewModel.drive(active: true, retryToken: 0)
        #expect(service.calls == 3)
        guard case .ready(let refreshed) = viewModel.state else {
            Issue.record("expected ready after retrying the failed refresh")
            return
        }
        #expect(refreshed.goods.first?.id == 6)
        #expect(!viewModel.refreshFailedHint)
    }

    @Test func busyRefreshRejectsSecondReTapWithoutNewRequest() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 7)), .gate, .value(Self.snapshot(goodsID: 8)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        let refresh = Task { await viewModel.drive(active: true, retryToken: 0) }
        await waitUntil({ service.calls == 2 })
        #expect(viewModel.isRefreshing)
        guard case .ready(let visible) = viewModel.state else {
            Issue.record("old content must stay visible during refresh")
            return
        }
        // Re-taps while the refresh hangs: rejected, no ticket change, the
        // active request is neither cancelled nor queued.
        viewModel.requestRefresh(2)
        #expect(viewModel.refreshTicket == 1)
        service.release(.success(Self.snapshot(goodsID: 8)))
        await refresh.value
        #expect(service.calls == 2)
        #expect(viewModel.state != .ready(visible))
    }

    @Test func firstLoadBusyAndIdleRejectReTap() async {
        let service = ScriptedService(steps: [.never])
        let viewModel = HomeViewModel(home: service)
        let load = Task { await viewModel.handleVisibility(true) }
        await waitUntil({ service.calls == 1 })
        viewModel.requestRefresh(1)
        #expect(viewModel.refreshTicket == 0)
        load.cancel()
        await load.value
        #expect(viewModel.state == .idle)
        // Idle also rejects: the visibility path will read when active.
        viewModel.requestRefresh(2)
        #expect(viewModel.refreshTicket == 0)
    }

    @Test func reTapOnFullPageFailureReloadsThroughFirstLoadUI() async {
        let service = ScriptedService(steps: [
            .failure(.timeout), .value(Self.snapshot(goodsID: 9)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .failed(.timeout) = viewModel.state else { return }
        viewModel.requestRefresh(1)
        await viewModel.drive(active: true, retryToken: 0)
        #expect(service.calls == 2)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after re-tap reload from full-page failure")
            return
        }
    }

    @Test func offPageCancelsRefreshKeepsContentAndDoesNotRefireOnReturn() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 10)), .gate, .value(Self.snapshot(goodsID: 11)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .ready = viewModel.state else { return }
        viewModel.requestRefresh(1)
        let refresh = Task { await viewModel.drive(active: true, retryToken: 0) }
        await waitUntil({ service.calls == 2 })
        // Leaving the page suspends: generation revoked, indicator closed,
        // late result discarded, old content retained.
        await viewModel.handleVisibility(false)
        #expect(!viewModel.isRefreshing)
        service.release(.success(Self.snapshot(goodsID: 11)))
        await refresh.value
        guard case .ready(let kept) = viewModel.state else {
            Issue.record("expected old content retained after cancelled refresh")
            return
        }
        #expect(kept.goods.first?.id == 10)
        // Returning must not re-fire the refresh.
        await viewModel.handleVisibility(true)
        #expect(service.calls == 2)
    }

    @Test func supersededRefreshCompletionCannotClearNewRefreshState() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 20)), .gate, .gate,
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .ready = viewModel.state else { return }
        viewModel.requestRefresh(1)
        let firstRefresh = Task { await viewModel.drive(active: true, retryToken: 0) }
        await waitUntil({ service.calls == 2 })
        await viewModel.handleVisibility(false)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(2)
        #expect(viewModel.refreshTicket == 2)
        let secondRefresh = Task { await viewModel.drive(active: true, retryToken: 0) }
        await waitUntil({ service.calls == 3 })
        // New refresh (B) settles first; the older suspended one (A) then
        // returns late — it must not clear flags or overwrite the new state.
        service.releaseLatest(.success(Self.snapshot(goodsID: 22)))
        await secondRefresh.value
        service.release(.success(Self.snapshot(goodsID: 21)))
        await firstRefresh.value
        guard case .ready(let snapshot) = viewModel.state else {
            Issue.record("expected the newer refresh result to win")
            return
        }
        #expect(snapshot.goods.first?.id == 22)
        #expect(!viewModel.isRefreshing)
        #expect(service.calls == 3)
    }
}
