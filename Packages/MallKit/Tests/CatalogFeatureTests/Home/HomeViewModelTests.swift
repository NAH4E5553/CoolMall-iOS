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
}
