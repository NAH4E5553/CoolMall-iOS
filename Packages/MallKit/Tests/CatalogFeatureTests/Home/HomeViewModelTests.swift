import Foundation
import MallCore
import SwiftUI
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
            /// Gate that records client-task cancellation and resumes the
            /// suspended call with a cancellation result (HOME-RETAP-LATEST).
            case cancelGate
        }

        private var steps: [Step]
        private(set) var calls = 0
        /// How many times a suspended `cancelGate` call observed its client
        /// task being cancelled — direct evidence of cancellation propagation.
        private(set) var cancellations = 0
        private var gated: [CheckedContinuation<Result<HomeSnapshot, Error>, Never>] = []
        private var cancelGated: [UUID: CheckedContinuation<Result<HomeSnapshot, Error>, Never>] =
            [:]

        init(steps: [Step]) {
            self.steps = steps
        }

        var pendingGates: Int { gated.count + cancelGated.count }

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
            case .cancelGate:
                let id = UUID()
                return try await withTaskCancellationHandler {
                    try await withCheckedContinuation { continuation in
                        cancelGated[id] = continuation
                    }.get()
                } onCancel: {
                    Task { @MainActor in
                        guard let continuation = self.cancelGated.removeValue(forKey: id) else {
                            return
                        }
                        self.cancellations += 1
                        continuation.resume(returning: .failure(CancellationError()))
                    }
                }
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

    /// Controllable virtual time for the 300ms merge window: sleeps register
    /// virtual-millisecond deadlines; `advance` resumes the due ones. This is
    /// the sub-second boundary evidence the contract asks for — no slow AX
    /// query can observe a 299/300ms edge.
    @MainActor
    final class ManualSleeper {
        private struct Waiter {
            let id: UUID
            let deadlineMs: Int64
            var continuation: CheckedContinuation<Void, Error>?
        }
        private var nowMs: Int64 = 0
        private var waiters: [Waiter] = []
        private(set) var sleepCount = 0
        /// Every duration actually handed to `sleep` — proves the task only
        /// waits the REMAINING time toward the acceptance deadline (R-DB-03).
        private(set) var requestedDurationsMs: [Int64] = []

        /// Virtual "elapsed since clock start" for the acceptance seam.
        var elapsed: ContinuousClock.Duration { .milliseconds(nowMs) }

        func sleep(_ duration: ContinuousClock.Duration) async throws {
            let components = duration.components
            let ms = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
            sleepCount += 1
            requestedDurationsMs.append(ms)
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    waiters.append(Waiter(id: id, deadlineMs: nowMs + ms, continuation: c))
                }
            } onCancel: {
                Task { @MainActor in self.cancelWaiter(id: id) }
            }
        }

        private func cancelWaiter(id: UUID) {
            guard let index = waiters.firstIndex(where: { $0.id == id }),
                let continuation = waiters[index].continuation
            else { return }
            waiters.remove(at: index)
            continuation.resume(throwing: CancellationError())
        }

        /// Moves the virtual clock WITHOUT yielding or resuming anything —
        /// the scheduled merge task stays unstarted (R-DB-03 delayed-start
        /// scenarios).
        func bump(ms: Int64) {
            nowMs += ms
        }

        /// Advances virtual time. The leading yield hops let the scheduled
        /// merge task actually register its sleeper waiter first — a freshly
        /// created Task is only enqueued, so advancing synchronously would
        /// compute the deadline from a later virtual "now".
        func advance(ms: Int64) async {
            for _ in 0..<8 { await Task.yield() }
            nowMs += ms
            while let index = waiters.firstIndex(where: { $0.deadlineMs <= nowMs }) {
                let waiter = waiters.remove(at: index)
                waiter.continuation?.resume()
            }
        }
    }

    /// Wires a view model to virtual time (sleep AND the acceptance elapsed
    /// seam) and returns the sleeper.
    @MainActor
    private func mergeClock(for viewModel: HomeViewModel) -> ManualSleeper {
        let sleeper = ManualSleeper()
        viewModel.retapMergeSleep = { try await sleeper.sleep($0) }
        viewModel.retapElapsedOverride = { sleeper.elapsed }
        return sleeper
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
        // The ORIGINAL input: the CALLER's (view-task) cancellation itself —
        // no explicit visibility event runs afterwards (R-OWN-01). Cancelling
        // the awaiting caller cancels its own owned read.
        task.cancel()
        await task.value
        #expect(viewModel.state == .idle)
    }

    /// R-OWN-01: cancelling the caller cancels its own read EVEN when the
    /// service ignores cancellation — a late VALUE must not commit (HEAD
    /// parity restored; the explicit-inactive variant stays separate below).
    @Test func callerCancelledFirstReadRejectsLateValueDespiteIgnoredCancel() async {
        let service = ScriptedService(steps: [.gate])
        let viewModel = HomeViewModel(home: service)
        let task = Task { await viewModel.handleVisibility(true) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        task.cancel()
        // The gate ignores cancellation: release FIRST, then await — the
        // still-current cancelled request must reject the late value.
        service.release(.success(Self.snapshot(goodsID: 77)))
        await task.value
        await waitUntil { service.pendingGates == 0 }
        #expect(viewModel.state == .idle, "an ignored cancellation's value must not commit")
    }

    /// R-OWN-01: same contract for a late PLAIN ERROR — idle, never failed.
    @Test func callerCancelledFirstReadRejectsLatePlainError() async {
        let service = ScriptedService(steps: [.gate])
        let viewModel = HomeViewModel(home: service)
        let task = Task { await viewModel.handleVisibility(true) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        task.cancel()
        service.release(.failure(HomeLoadFailure.timeout))
        await task.value
        await waitUntil { service.pendingGates == 0 }
        #expect(viewModel.state == .idle)
    }

    /// R-OWN-01: the ORIGINAL retry's caller cancellation restores the
    /// retained failure — distinct from the explicit visibility-loss input.
    @Test func callerCancelledOriginalRetryRestoresRetainedFailure() async {
        let service = ScriptedService(steps: [.failure(.timeout), .gate])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .failed = viewModel.state else { return }
        let retryTask = Task { await viewModel.retry() }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        retryTask.cancel()
        service.release(.success(Self.snapshot(goodsID: 78)))
        await retryTask.value
        await waitUntil { service.pendingGates == 0 }
        guard case .failed(.timeout) = viewModel.state else {
            Issue.record("caller-cancelled retry must restore the retained failure")
            return
        }
    }

    /// R-OWN-01: a STALE caller's cancellation (arriving after a re-tap took
    /// over) must not cancel the newer request or disturb its loading state.
    @Test func staleCallerCancellationCannotTouchNewerRetapRequest() async {
        let service = ScriptedService(steps: [.cancelGate, .value(Self.snapshot(goodsID: 5))])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        let firstLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        // The re-tap takes over: the first read is really cancelled by the
        // owner; the stale caller THEN cancels itself — the newer request
        // must be untouched (exactly one real cancellation in total).
        viewModel.requestRefresh(1)
        await waitUntil { service.cancellations == 1 }
        firstLoad.cancel()
        await firstLoad.value
        #expect(viewModel.isRetapPending)
        await sleeper.advance(ms: 300)
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 5)) }
        #expect(service.cancellations == 1, "the stale caller's cancel added no cancellation")
        #expect(service.calls == 2)
    }

    /// The explicit visibility-loss input stays covered SEPARATELY from the
    /// caller-cancellation input above (both are real product paths).
    @Test func explicitVisibilityLossSuspendsFirstReadToIdle() async {
        let service = ScriptedService(steps: [.never])
        let viewModel = HomeViewModel(home: service)
        let task = Task { await viewModel.handleVisibility(true) }
        await waitUntil { service.calls == 1 }
        await viewModel.handleVisibility(false)
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
        // The product cancellation path for an owned retry is the
        // visibility loss (suspend), which really cancels the read task.
        await viewModel.handleVisibility(false)
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
        // The still-current request is cancelled by the visibility loss; the
        // gated service ignores that and returns a value anyway.
        await viewModel.handleVisibility(false)
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
        await viewModel.handleVisibility(false)
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
        // Leaving the page: the drive restart with active=false suspends —
        // the owned in-flight retry is really cancelled and the retained
        // failure restored; its late success is discarded.
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

    // MARK: HOME-RETAP-DEBOUNCE — 300ms trailing merge (2026-10-20)

    /// A single re-tap waits the FULL window: no read before the deadline,
    /// exactly one read at it. The re-tap path never bumps the immediate
    /// ticket, and a redelivered SAME token neither re-processes nor opens a
    /// new window.
    @Test func singleRetapReadsOnlyAfterFullWindowAndOnlyOnce() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        guard case .ready = viewModel.state else { return }
        viewModel.requestRefresh(1)
        #expect(viewModel.isRetapPending, "window is pending right after the tap")
        #expect(viewModel.refreshTicket == 0, "the merged re-tap path owns no ticket")
        await sleeper.advance(ms: 299)
        #expect(service.calls == 1, "no read before the full window elapses")
        await sleeper.advance(ms: 1)
        await waitUntil { service.calls == 2 }
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
        #expect(!viewModel.isRetapPending)
        #expect(!viewModel.isRefreshing)
        #expect(sleeper.sleepCount == 1)
        // Same token redelivery: deduplicated, no new window.
        viewModel.requestRefresh(1)
        #expect(sleeper.sleepCount == 1)
        #expect(viewModel.isRetapPending == false)
        await sleeper.advance(ms: 1000)
        #expect(service.calls == 2, "exactly one read for the whole batch")
    }

    /// The contract's own example: taps at virtual 0/100/220ms merge into
    /// ONE read that starts only after the LAST tap's 300ms deadline.
    @Test func consecutiveRetapsMergeIntoOneBatchAtLastDeadline() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 100)
        viewModel.requestRefresh(2)
        await sleeper.advance(ms: 120)
        viewModel.requestRefresh(3)
        // Virtual time is now 220; the deadline is 220+300 = 520.
        await sleeper.advance(ms: 299)
        #expect(service.calls == 1, "one millisecond before the last deadline: no read")
        await sleeper.advance(ms: 1)
        await waitUntil { service.calls == 2 }
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
        #expect(sleeper.sleepCount == 3, "each distinct tap re-armed the timer")
        #expect(service.calls == 2, "the whole burst produced exactly one read")
    }

    /// A redelivered SAME token does not push the deadline out: the read
    /// still fires at the FIRST tap's +300ms.
    @Test func sameTokenRedeliveryDoesNotResetDeadline() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 100)
        viewModel.requestRefresh(1)
        #expect(sleeper.sleepCount == 1, "duplicate token must not re-arm")
        await sleeper.advance(ms: 200)
        await waitUntil { service.calls == 2 }
        #expect(service.calls == 2, "read fired at the original 300ms deadline")
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
    }

    /// A re-tap DURING a pending window replaces the timer wholesale: the
    /// old deadline never fires; only the new tap's deadline does.
    @Test func retapDuringMergeWindowReplacesPendingTimer() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 150)
        viewModel.requestRefresh(2)
        await waitUntil { sleeper.sleepCount == 2 }
        await sleeper.advance(ms: 149)
        #expect(service.calls == 1, "old deadline (150) is long gone; new is 450")
        await sleeper.advance(ms: 151)
        await waitUntil { service.calls == 2 }
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
    }

    @Test func reTapFromEmptyCanProduceReady() async {
        let service = ScriptedService(steps: [
            .value(Self.emptySnapshot), .value(Self.snapshot(goodsID: 3)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        guard case .empty = viewModel.state else { return }
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 }
        await waitUntil {
            if case .ready = viewModel.state { return true }
            return false
        }
    }

    @Test func reTapOnFullPageFailureReloadsThroughFirstLoadUI() async {
        let service = ScriptedService(steps: [
            .failure(.timeout), .value(Self.snapshot(goodsID: 9)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        guard case .failed(.timeout) = viewModel.state else { return }
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 }
        await waitUntil {
            if case .ready = viewModel.state { return true }
            return false
        }
    }

    /// A failed merged refresh keeps the old content behind the hint; the
    /// hint's OWN retry stays an IMMEDIATE entry (original contract) and its
    /// read runs without any window.
    @Test func refreshFailureKeepsOldContentHintAndRetryRefreshSucceeds() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 5)), .failure(.timeout),
            .value(Self.snapshot(goodsID: 6)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        guard case .ready(let committed) = viewModel.state else { return }
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { viewModel.refreshFailedHint }
        #expect(viewModel.state == .ready(committed))
        #expect(!viewModel.isRefreshing)
        viewModel.requestRetryRefresh()
        #expect(viewModel.refreshTicket == 1, "the hint retry is an immediate entry")
        await waitUntil { service.calls == 3 }
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 6)) }
        #expect(!viewModel.refreshFailedHint)
    }

    // MARK: supersede & stale-outcome isolation

    /// A re-tap during an in-flight merged read supersedes it at arrival —
    /// the OWNER cancels the old task — and starts a fresh window; the old
    /// read's late value (its service ignores cancellation) can neither
    /// commit nor clear the new batch's indicator.
    @Test func retapDuringInFlightReadSupersedesAndMergesNewBatch() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 7)), .gate, .gate,
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        #expect(viewModel.isRefreshing)
        guard case .ready(let visible) = viewModel.state else {
            Issue.record("old content must stay visible during refresh")
            return
        }
        // DISTINCT re-tap while the read hangs: accepted at once, the old
        // identity is dead and a new window is pending. The product owner
        // cancelled the old task; no test-side cancel is performed.
        viewModel.requestRefresh(2)
        #expect(viewModel.isRetapPending)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 3 && service.pendingGates == 2 }
        // The superseded read (gate #1) returns LATE with a value.
        service.release(.success(Self.snapshot(goodsID: 99)))
        await waitUntil { service.pendingGates == 1 }
        #expect(viewModel.isRefreshing, "stale completion must not clear the indicator")
        #expect(viewModel.state == .ready(visible))
        service.releaseLatest(.success(Self.snapshot(goodsID: 8)))
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 8)) }
        #expect(!viewModel.isRefreshing)
        #expect(service.calls == 3)
    }

    /// A re-tap during the FIRST read waits its window and reloads through
    /// the loading UI; the first read's late value is rejected.
    @Test func retapDuringFirstLoadWaitsWindowAndLateFirstValueIsRejected() async {
        let service = ScriptedService(steps: [.gate, .gate])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        let firstLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        #expect(viewModel.state == .loading)
        viewModel.requestRefresh(1)
        #expect(viewModel.isRetapPending)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 2 }
        #expect(viewModel.state == .loading, "the merged reload keeps the loading UI")
        service.release(.success(Self.snapshot(goodsID: 77)))
        await waitUntil { service.pendingGates == 1 }
        #expect(viewModel.state == .loading, "the superseded first read must not commit")
        service.releaseLatest(.success(Self.snapshot(goodsID: 8)))
        await firstLoad.value
        await waitUntil {
            if case .ready(let snapshot) = viewModel.state {
                return snapshot.goods.first?.id == 8
            }
            return false
        }
    }

    /// A superseded refresh that FAILS late can neither surface the failure
    /// hint nor clear the newer request's indicator.
    @Test func supersededRefreshLateFailureCannotSetHintOrClearIndicator() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 50)), .gate, .gate,
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        viewModel.requestRefresh(2)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 3 && service.pendingGates == 2 }
        service.release(.failure(HomeLoadFailure.httpStatus(503)))
        await waitUntil { service.pendingGates == 1 }
        #expect(!viewModel.refreshFailedHint, "superseded failure must not set the hint")
        #expect(viewModel.isRefreshing, "superseded cleanup must not clear the indicator")
        service.releaseLatest(.success(Self.snapshot(goodsID: 51)))
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 51)) }
        #expect(!viewModel.isRefreshing)
    }

    /// REAL cancellation wiring: the superseded request's own cancellation
    /// handler observes the cancel issued by the product owner (no test
    /// cancels anything), and the new batch reads after its window.
    @Test func retapSupersedeCancelsOldClientTaskThroughRealOwner() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 60)), .cancelGate, .value(Self.snapshot(goodsID: 61)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        // The distinct re-tap makes the OWNER cancel the in-flight task.
        viewModel.requestRefresh(2)
        await waitUntil { service.cancellations == 1 }
        #expect(viewModel.isRetapPending)
        await sleeper.advance(ms: 300)
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 61)) }
        #expect(service.calls == 3)
        #expect(!viewModel.isRefreshing)
    }

    /// Leaving the page between batches invalidates the old request by
    /// visibility; a NEW re-tap batch then wins over the stale completion.
    @Test func supersededRefreshCompletionCannotClearNewRefreshState() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 20)), .gate, .gate,
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        guard case .ready = viewModel.state else { return }
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        await viewModel.handleVisibility(false)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(2)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 3 && service.pendingGates == 2 }
        // New refresh (B) settles first; the older suspended one (A) then
        // returns late — it must not clear flags or overwrite the new state.
        service.releaseLatest(.success(Self.snapshot(goodsID: 22)))
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 22)) }
        #expect(!viewModel.isRefreshing)
        service.release(.success(Self.snapshot(goodsID: 21)))
        await waitUntil { service.pendingGates == 0 }
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 22)))
        #expect(!viewModel.isRefreshing)
        #expect(service.calls == 3)
    }

    // MARK: pull & immediate entries keep their ORIGINAL contracts

    /// Pulls stay immediate-or-rejected: an accepted pull reads at once (no
    /// window); a second pull while its read hangs is REJECTED — nothing
    /// queues and the ticket does not move.
    @Test func pullReadsImmediatelyAndBusyPullDoesNotQueue() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .gate, .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        var pullEnded = false
        let pull = Task {
            await viewModel.pullToRefresh(); pullEnded = true
        }
        await waitUntil { viewModel.refreshTicket == 1 }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        #expect(!pullEnded)
        #expect(viewModel.isRefreshing)
        // Busy pull: rejected, no new request, no queue.
        await viewModel.pullToRefresh()
        #expect(viewModel.refreshTicket == 1)
        #expect(service.calls == 2)
        service.release(.success(Self.snapshot(goodsID: 2)))
        await waitUntil { pullEnded }
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
        _ = sleeper
    }

    /// A re-tap supersedes an in-flight pull: the pull's waiter ends
    /// PROMPTLY (before the new batch's window expires), the pull's read is
    /// cancelled by the owner, and the new batch reads after its window.
    @Test func retapSupersedesInFlightPullAndEndsWaiterBeforeNewRead() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .cancelGate, .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        var pullEnded = false
        let pull = Task {
            await viewModel.pullToRefresh(); pullEnded = true
        }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        viewModel.requestRefresh(1)
        await waitUntil { pullEnded }
        #expect(viewModel.isRetapPending, "the pull ended while the window is still pending")
        await waitUntil { service.cancellations == 1 }
        #expect(service.calls == 2, "no new read before the window expires")
        await sleeper.advance(ms: 300)
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
        #expect(service.calls == 3)
    }

    /// A pull during a pending merge window is busy: rejected without a new
    /// request and WITHOUT disturbing the window's deadline; after the batch
    /// completes, a fresh pull reads again (original immediate contract).
    @Test func pullDuringMergeWindowIsRejectedWithoutDisturbingWindow() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
            .value(Self.snapshot(goodsID: 3)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 150)
        await viewModel.pullToRefresh(interaction: 1)
        #expect(viewModel.refreshTicket == 0, "the busy pull must not accept")
        #expect(service.calls == 1)
        await sleeper.advance(ms: 150)
        await waitUntil { service.calls == 2 }
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
        #expect(sleeper.sleepCount == 1, "the rejected pull never re-armed the window")
        // After the batch settles the pull contract is intact.
        let pull = Task { await viewModel.pullToRefresh(interaction: 2) }
        await waitUntil { viewModel.refreshTicket == 1 }
        await waitUntil { service.calls == 3 }
        await pull.value
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 3)) }
    }

    @Test func failedPullEndsAndKeepsCommittedContent() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .failure(.timeout),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        var pullEnded = false
        let pull = Task {
            await viewModel.pullToRefresh(); pullEnded = true
        }
        await waitUntil { pullEnded }
        #expect(viewModel.refreshFailedHint)
        #expect(!viewModel.isRefreshing)
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 1)))
    }

    /// A cancelled old waiter cannot end a NEW pull's wait or clear its read.
    @Test func oldWaiterCannotEndNewPullWaiter() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .gate, .gate,
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        var oldPullEnded = false
        let oldPull = Task {
            await viewModel.pullToRefresh(); oldPullEnded = true
        }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        await viewModel.handleVisibility(false)
        await oldPull.value
        #expect(oldPullEnded)
        await viewModel.handleVisibility(true)
        var newPullEnded = false
        let newPull = Task {
            await viewModel.pullToRefresh(); newPullEnded = true
        }
        await waitUntil { viewModel.refreshTicket == 2 }
        await waitUntil { service.calls == 3 && service.pendingGates == 2 }
        // The OLD suspended read returns late — it must not end the new wait.
        service.release(.success(Self.snapshot(goodsID: 99)))
        await waitUntil { service.pendingGates == 1 }
        #expect(!newPullEnded)
        #expect(viewModel.isRefreshing)
        service.releaseLatest(.success(Self.snapshot(goodsID: 2)))
        await newPull.value
        #expect(newPullEnded)
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 2)))
    }

    /// Recovery keeps its original immediate-and-busy-rejected contract; a
    /// re-tap may supersede the recovery's read, and the superseded outcome
    /// cannot commit.
    @Test func recoveryIsImmediateAndRetapMaySupersedeIt() async {
        let service = ScriptedService(steps: [
            .failure(.timeout), .gate, .value(Self.snapshot(goodsID: 1)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        guard case .failed = viewModel.state else { return }
        viewModel.requestUserRetry()
        #expect(viewModel.refreshTicket == 1)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        // Second recovery while busy: rejected (original contract).
        viewModel.requestUserRetry()
        #expect(viewModel.refreshTicket == 1)
        // A DISTINCT re-tap supersedes the hanging recovery read.
        viewModel.requestRefresh(2)
        #expect(viewModel.isRetapPending)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 3 }
        service.release(.success(Self.snapshot(goodsID: 1)))
        await waitUntil { service.pendingGates == 0 }
        #expect(
            viewModel.state == .ready(Self.snapshot(goodsID: 1)),
            "the superseded completion must not disturb the latest batch's result")
    }

    @Test func duplicatePullInteractionCannotReadAgainAfterCompletion() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
            .value(Self.snapshot(goodsID: 3)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        let first = Task { await viewModel.pullToRefresh(interaction: 1) }
        await waitUntil { viewModel.refreshTicket == 1 }
        await first.value
        await waitUntil { service.calls == 2 }
        await viewModel.pullToRefresh(interaction: 1)
        #expect(service.calls == 2)
        #expect(viewModel.refreshTicket == 1)
        let second = Task { await viewModel.pullToRefresh(interaction: 2) }
        await waitUntil { viewModel.refreshTicket == 2 }
        await second.value
        await waitUntil { service.calls == 3 }
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 3)))
    }

    /// A pull rejected while the merge window is pending stays deduplicated
    /// afterwards; the accessibility entry keeps its original contract.
    @Test func busyPullReplayStaysDedupedAndAccessibleEntryReadsWhenIdle() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
            .value(Self.snapshot(goodsID: 3)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        // Busy while the window is pending.
        await viewModel.pullToRefresh(interaction: 1)
        #expect(viewModel.refreshTicket == 0)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 }
        // The rejected interaction's replay after the batch ends: still a
        // duplicate, never accepted.
        await viewModel.pullToRefresh(interaction: 1)
        #expect(viewModel.refreshTicket == 0)
        #expect(service.calls == 2)
        viewModel.requestAccessibleRefresh()
        #expect(viewModel.refreshTicket == 1)
        await waitUntil { service.calls == 3 }
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 3)) }
    }

    @Test func alreadyCancelledPullDoesNotAcceptOrRegister() async {
        let service = ScriptedService(steps: [.value(Self.snapshot(goodsID: 1))])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        let pull = Task { await viewModel.pullToRefresh(interaction: 1) }
        // This MainActor test has not yielded, so cancellation precedes entry.
        pull.cancel()
        await pull.value
        #expect(viewModel.refreshTicket == 0)
        #expect(service.calls == 1)
    }

    /// Cancelling the PULL WAIT (the refreshable's own task) ends only that
    /// wait; the owned read continues and a later ticket still works.
    @Test func cancellingPullWaitDoesNotCancelOwnedReadOrClearNextTicket() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .gate, .value(Self.snapshot(goodsID: 3)),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        var ended = false
        let pull = Task {
            await viewModel.pullToRefresh(interaction: 1); ended = true
        }
        await waitUntil { viewModel.refreshTicket == 1 }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        pull.cancel()
        await waitUntil { ended }
        #expect(viewModel.isRefreshing, "only the wait ended; the owned read still runs")
        service.release(.success(Self.snapshot(goodsID: 2)))
        await waitUntil { !viewModel.isRefreshing }
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 2)))
        var nextEnded = false
        let next = Task {
            await viewModel.pullToRefresh(interaction: 2); nextEnded = true
        }
        await waitUntil { viewModel.refreshTicket == 2 }
        await next.value
        await waitUntil { service.calls == 3 }
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 3)))
    }

    /// An accepted pull's read is really cancelled by an immediate
    /// visibility loss — observed by the read's own cancellation handler
    /// (R-OWN-01 wiring); returning never re-fires it. The old
    /// "accepted-but-unstarted" window no longer exists: acceptance now
    /// occupies busy synchronously AND starts the read eagerly (R-DB-02),
    /// so scheduling may or may not reach the service first — the
    /// deterministic assertion is the real cancellation, not the call count.
    @Test func acceptedPullReadIsReallyCancelledOnLeaveWithoutRefire() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .cancelGate,
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        var pullEnded = false
        let pull = Task {
            await viewModel.pullToRefresh(); pullEnded = true
        }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        await viewModel.handleVisibility(false)
        await pull.value
        #expect(pullEnded)
        await waitUntil { service.cancellations == 1 }
        #expect(!viewModel.isRefreshing)
        await viewModel.handleVisibility(true)
        #expect(service.calls == 2, "returning must not re-fire the cancelled pull read")
    }

    /// The hint retry keeps its original busy rejection: a second acceptance
    /// while its read hangs never starts another request.
    @Test func retryRefreshSlotRejectsSecondAcceptanceWhileBusy() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 34)), .failure(.timeout), .gate,
            .value(Self.snapshot(goodsID: 35)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { viewModel.refreshFailedHint }
        viewModel.requestRetryRefresh()
        #expect(viewModel.refreshTicket == 1)
        await waitUntil { service.calls == 3 && service.pendingGates == 1 }
        // Second retry acceptance while the first retry's read hangs:
        // rejected (original immediate-entry contract).
        viewModel.requestRetryRefresh()
        viewModel.requestAccessibleRefresh()
        #expect(viewModel.refreshTicket == 1)
        service.release(.success(Self.snapshot(goodsID: 35)))
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 35)) }
        #expect(service.calls == 3)
    }

    // MARK: lifecycle — leave during window / during read

    /// Leaving during the merge window drops the intent: no read ever fires
    /// (even after the full window), returning does not replay it, and no
    /// request hides off-page.
    @Test func retapWindowIsDroppedOnLeaveWithoutReadOrReplay() async {
        let service = ScriptedService(steps: [.value(Self.snapshot(goodsID: 1))])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 200)
        #expect(service.calls == 1)
        await viewModel.handleVisibility(false)
        #expect(!viewModel.isRetapPending)
        await sleeper.advance(ms: 1000)
        #expect(service.calls == 1, "the dropped intent must never read")
        await viewModel.handleVisibility(true)
        #expect(service.calls == 1, "returning must not replay the dropped re-tap")
    }

    /// Leaving while a merged read is in flight cancels it, keeps the
    /// committed content, and never re-fires on return.
    @Test func offPageCancelsInFlightRetapReadKeepsContentAndDoesNotRefire() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 10)), .gate, .value(Self.snapshot(goodsID: 11)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        guard case .ready = viewModel.state else { return }
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        await viewModel.handleVisibility(false)
        #expect(!viewModel.isRefreshing)
        service.release(.success(Self.snapshot(goodsID: 11)))
        await waitUntil { service.pendingGates == 0 }
        guard case .ready(let kept) = viewModel.state else {
            Issue.record("expected old content retained after cancelled refresh")
            return
        }
        #expect(kept.goods.first?.id == 10)
        await viewModel.handleVisibility(true)
        #expect(service.calls == 2, "returning must not re-fire the refresh")
    }

    // MARK: R-OWN-01-LIFE — page teardown after the first read finished

    /// R-OWN-01-LIFE: the entry's `.task` has RETURNED after the first read
    /// committed; a re-tap then arms the 300ms merge timer owned only by the
    /// VM's task. Teardown (the real entry calls `pageTeardown()` from
    /// `onDisappear`) must drop the pending intent: the window may expire
    /// afterwards WITHOUT any second read.
    @Test func pageTeardownAfterFirstLoadDropsPendingRetapWindow() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        // The real entry drive shape: the view task runs the first read and
        // COMPLETES (no lasting await exists afterwards).
        let viewTask = Task { await viewModel.drive(active: true, retryToken: 0) }
        await viewTask.value
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 1)))
        // A real re-tap arms the merge window (nothing else is in flight).
        viewModel.requestRefresh(1)
        #expect(viewModel.isRetapPending)
        // Page teardown — NOT a caller-task cancel (that task already
        // finished) and NOT a drive(active:false).
        viewModel.pageTeardown()
        #expect(!viewModel.isRetapPending)
        #expect(!viewModel.hasPendingOwnedRequest)
        // The full window (and far beyond) elapses: no second read, ever.
        await sleeper.advance(ms: 5_000)
        #expect(service.calls == 1, "the dropped intent must not read after teardown")
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 1)))
    }

    /// R-OWN-01-LIFE: an in-flight MERGED refresh is REALLY cancelled by
    /// teardown — the read's own cancellation handler observes it (no
    /// test-side cancel). This is the responsive-cancellation branch; the
    /// ignore-cancel late-return branch is covered separately below with a
    /// gate that is still pending when its late result arrives.
    @Test func pageTeardownReallyCancelsInFlightRetapRefresh() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .cancelGate,
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        let viewTask = Task { await viewModel.drive(active: true, retryToken: 0) }
        await viewTask.value
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        #expect(viewModel.isRefreshing)
        // Teardown: the in-flight read is cancelled for real — the
        // cancellation-responsive service observes it and ENDS itself.
        viewModel.pageTeardown()
        await waitUntil { service.cancellations == 1 }
        #expect(!viewModel.isRefreshing)
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 1)))
        #expect(service.calls == 2)
        #expect(service.pendingGates == 0, "the responsive read left nothing pending")
    }

    /// R-OWN-01-LIFE, ignore-cancel branch: a read that IGNORES teardown
    /// cancellation stays pending on its gate; its LATE VALUE must not
    /// commit when released afterwards.
    @Test func pageTeardownRejectsLateValueFromIgnoredCancelInFlightRefresh() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .gate,
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        let viewTask = Task { await viewModel.drive(active: true, retryToken: 0) }
        await viewTask.value
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        viewModel.pageTeardown()
        #expect(!viewModel.isRefreshing)
        // The gate ignores cancellation: the request is STILL pending —
        // releasing it now delivers a genuinely late value.
        #expect(service.pendingGates == 1, "the ignore-cancel read is still pending")
        service.release(.success(Self.snapshot(goodsID: 99)))
        await waitUntil { service.pendingGates == 0 }
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 1)))
        #expect(service.calls == 2)
    }

    /// R-OWN-01-LIFE: teardown ends an accepted pull's WAITER promptly
    /// (finishRefresh at teardown, while the ignore-cancel read is still
    /// pending on its gate); the read's LATE PLAIN ERROR afterwards can
    /// neither surface as a failure hint nor disturb the kept content.
    @Test func pageTeardownEndsPullWaiterAndRejectsLateErrorFromIgnoredCancel() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .gate,
        ])
        let viewModel = HomeViewModel(home: service)
        let viewTask = Task { await viewModel.drive(active: true, retryToken: 0) }
        await viewTask.value
        var pullEnded = false
        let pull = Task {
            await viewModel.pullToRefresh(interaction: 1); pullEnded = true
        }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        viewModel.pageTeardown()
        await pull.value
        #expect(pullEnded, "the pull waiter ends promptly at teardown")
        #expect(service.pendingGates == 1, "the ignore-cancel read is still pending")
        service.release(.failure(HomeLoadFailure.httpStatus(503)))
        await waitUntil { service.pendingGates == 0 }
        #expect(!viewModel.refreshFailedHint, "a late error after teardown must not hint")
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 1)))
    }

    /// R-OWN-01-LIFE: teardown is the page's TERMINAL cleanup — it ends ALL
    /// of the removed page's current intents (including one that had just
    /// taken over an older hanging read), a SECOND teardown is a harmless
    /// no-op, and reactivation never replays any dropped intent.
    @Test func pageTeardownEndsAllCurrentPageIntentsIdempotentlyWithoutReplay() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .gate, .value(Self.snapshot(goodsID: 4)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        let viewTask = Task { await viewModel.drive(active: true, retryToken: 0) }
        await viewTask.value
        // A first retap's read hangs; a second retap takes over; teardown then
        // ends BOTH (the newer intent belongs to the same removed page).
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        viewModel.requestRefresh(2)
        #expect(viewModel.isRetapPending)
        viewModel.pageTeardown()
        viewModel.pageTeardown()
        #expect(!viewModel.isRetapPending)
        await sleeper.advance(ms: 5_000)
        #expect(service.calls == 2)
        // Reactivating the page never replays the dropped intents.
        await viewModel.handleVisibility(true)
        #expect(service.calls == 2, "returning must not replay dropped intents")
        // Cleanup: release the ignore-cancel hanging read so no task leaks.
        #expect(service.pendingGates == 1)
        service.release(.success(Self.snapshot(goodsID: 4)))
        await waitUntil { service.pendingGates == 0 }
        #expect(viewModel.state == .ready(Self.snapshot(goodsID: 1)))
    }

    /// The positive and disappearance cases share a BUSINESS acknowledgement:
    /// a second re-tap really cancels a pending read inside the real Entry.
    /// Keeping the window mounted must then execute the newly armed batch.
    @Test func realEntryHostPositiveControlRetapReadsWhileMounted() async throws {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .cancelGate,
            .value(Self.snapshot(goodsID: 2)),
        ])
        let (host, window) = mountRealEntry(service: service)
        defer { removeRealEntry(host: host, window: window) }
        try await armRealEntryRetapWindow(host: host, service: service)
        let didRead = try await waitForHost { service.calls >= 3 }
        try #require(didRead, "the acknowledged batch must read while mounted")
        #expect(service.calls == 3)
        #expect(service.cancellations == 1)
    }

    /// Window-removal scope only; does not claim real-device Scene shutdown
    /// or forced process termination. The precondition is a real cancellation
    /// of the previous read, not a shell callback or a service-start count.
    @Test func realEntryOnDisappearTearsDownPendingRetapWindow() async throws {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .cancelGate,
            .value(Self.snapshot(goodsID: 2)),
        ])
        let (host, window) = mountRealEntry(service: service)
        defer { removeRealEntry(host: host, window: window) }
        try await armRealEntryRetapWindow(host: host, service: service)
        removeRealEntry(host: host, window: window)
        // Preserve the existing four-window observation period. A disconnected
        // onDisappear must now cause read #3 and fail this exact assertion.
        try await Task.sleep(for: .seconds(1.2))
        #expect(
            service.calls == 2,
            "the acknowledged merge window must die with the removed entry")
        #expect(service.cancellations == 1)
    }

    /// Stable shell identity preserves the real Entry and its VM when the
    /// public refreshRequest input changes, just as the App does.
    private struct RealEntryShell: View {
        let home: any HomeLoading
        var token: UInt64
        var body: some View {
            HomeEntryView(home: home, isActive: true, refreshRequest: token)
        }
    }

    @MainActor
    private func mountRealEntry(
        service: ScriptedService
    ) -> (UIHostingController<RealEntryShell>, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIHostingController(rootView: RealEntryShell(home: service, token: 0))
        window.rootViewController = host
        window.makeKeyAndVisible()
        return (host, window)
    }

    /// First deliver one real re-tap and wait for its cancellation-responsive
    /// service gate. Deliver another real token, then observe that SAME request
    /// being cancelled. Only Entry.requestRefresh can cause that transition:
    /// it synchronously invalidates the old request and arms the new deadline.
    /// The original first-read caller is now stale and cannot cancel this batch.
    @MainActor
    private func armRealEntryRetapWindow(
        host: UIHostingController<RealEntryShell>, service: ScriptedService
    ) async throws {
        let didLoad = try await waitForHost { service.calls >= 1 }
        try #require(didLoad, "the mounted entry must perform its initial read")
        try #require(service.calls == 1)
        host.rootView = RealEntryShell(home: service, token: 1)
        let didHang = try await waitForHost { service.calls >= 2 }
        try #require(didHang, "the first real re-tap must reach the service")
        try #require(service.calls == 2 && service.pendingGates == 1)
        try #require(service.cancellations == 0)

        host.rootView = RealEntryShell(home: service, token: 2)
        let didCancel = try await waitForHost { service.cancellations >= 1 }
        try #require(didCancel, "the real Entry must acknowledge the replacement by cancellation")
        try #require(service.cancellations == 1 && service.pendingGates == 0)
        // If a slow host consumed the window, fail the PRECONDITION rather
        // than attributing an already-started read to disappearance cleanup.
        try #require(service.calls == 2, "the acknowledged batch must still be waiting")
    }

    /// Poll a concrete business event while yielding to the host run loop.
    /// This bounds host preparation; it does not enlarge the 300ms contract.
    @MainActor
    private func waitForHost(_ condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

    @MainActor
    private func removeRealEntry(host: UIHostingController<RealEntryShell>, window: UIWindow) {
        window.rootViewController = nil
        host.view.removeFromSuperview()
        window.isHidden = true
    }
    // MARK: R-OWN-02 — original retry()/drive-retry full-page reload mode

    /// R-OWN-02: the ORIGINAL retry from EMPTY is a full-page reload — it
    /// enters loading first, and a failure becomes failed(error) with NO
    /// refresh hint (HEAD semantics restored).
    @Test func originalRetryFromEmptyReloadsFullPageAndFailsToFailed() async {
        let service = ScriptedService(steps: [
            .value(Self.emptySnapshot), .failure(.timeout),
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .empty = viewModel.state else { return }
        let retryTask = Task { await viewModel.retry() }
        await retryTask.value
        guard case .failed(.timeout) = viewModel.state else {
            Issue.record("original retry from empty must fail to failed(error)")
            return
        }
        #expect(!viewModel.refreshFailedHint, "no refresh hint on the reload path")
        // The drive retry-token path shares the same reload semantics (the
        // retry read needs its own scripted step).
        let second = ScriptedService(steps: [
            .failure(.networkUnavailable), .failure(.networkUnavailable),
        ])
        let secondVM = HomeViewModel(home: second)
        await secondVM.handleVisibility(true)
        guard case .failed = secondVM.state else { return }
        await secondVM.drive(active: true, retryToken: 7)
        guard case .failed(.networkUnavailable) = secondVM.state else {
            Issue.record("drive retry from failed must stay failed(error)")
            return
        }
    }

    /// R-OWN-02: the original retry from empty enters LOADING while waiting;
    /// a caller cancellation restores the retained EMPTY snapshot.
    @Test func originalRetryFromEmptyShowsLoadingAndCancelRestoresRetainedEmpty() async {
        let service = ScriptedService(steps: [.value(Self.emptySnapshot), .gate])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        guard case .empty = viewModel.state else { return }
        let retryTask = Task { await viewModel.retry() }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        #expect(viewModel.state == .loading, "the reload path enters loading first")
        retryTask.cancel()
        service.release(.success(Self.snapshot(goodsID: 79)))
        await retryTask.value
        await waitUntil { service.pendingGates == 0 }
        guard case .empty = viewModel.state else {
            Issue.record("cancelled original retry must restore the retained empty")
            return
        }
        #expect(!viewModel.refreshFailedHint)
    }

    /// R-OWN-02 scope guard: the EXPLICIT refresh of a valid empty snapshot
    /// (re-tap path) keeps its retained-content semantics — old empty stays
    /// behind the hint on failure; nothing changed for it.
    @Test func explicitRetapRefreshOfEmptyStillKeepsSnapshotBehindHint() async {
        let service = ScriptedService(steps: [
            .value(Self.emptySnapshot), .failure(.timeout),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        guard case .empty = viewModel.state else { return }
        viewModel.requestRefresh(1)
        await sleeper.advance(ms: 300)
        await waitUntil { viewModel.refreshFailedHint }
        guard case .empty = viewModel.state else {
            Issue.record("explicit refresh keeps the valid empty snapshot")
            return
        }
        #expect(viewModel.refreshFailedHint)
    }

    // MARK: R-DB-01/02/03 formal coverage (2026-10-20 independent review)

    /// R-DB-01: a re-tap REALLY cancels a cancellation-responsive FIRST read
    /// through the single owner — observed by the read's own cancellation
    /// handler, with no test-side cancel — then the merged batch reads.
    @Test func retapSupersedesCancellationResponsiveFirstLoadForReal() async {
        let service = ScriptedService(steps: [.cancelGate, .value(Self.snapshot(goodsID: 8))])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        let firstLoad = Task { await viewModel.handleVisibility(true) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        #expect(service.cancellations == 0)
        viewModel.requestRefresh(1)
        await waitUntil { service.cancellations == 1 }
        #expect(viewModel.isRetapPending)
        #expect(service.calls == 1, "no new read before the window expires")
        await sleeper.advance(ms: 300)
        await firstLoad.value
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 8)) }
        #expect(service.calls == 2)
    }

    /// R-DB-01: the ORIGINAL retry read (drive retry-token path) is equally
    /// owned and really cancelled when a re-tap supersedes it.
    @Test func retapSupersedesOriginalRetryReadForReal() async {
        let service = ScriptedService(steps: [
            .failure(.timeout), .cancelGate, .value(Self.snapshot(goodsID: 3)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.drive(active: true, retryToken: 0)
        guard case .failed = viewModel.state else { return }
        let retryTask = Task { await viewModel.drive(active: true, retryToken: 1) }
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        viewModel.requestRefresh(1)
        await waitUntil { service.cancellations == 1 }
        await sleeper.advance(ms: 300)
        await retryTask.value
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 3)) }
        #expect(service.calls == 3)
    }

    /// R-DB-02: the FIRST immediate acceptance occupies the busy slot
    /// synchronously — a second immediate entry in the SAME actor turn,
    /// before the first intent's Task has run, is rejected without changing
    /// the ticket, cancelling or replacing the first intent; a pull while
    /// the first read hangs is rejected likewise.
    @Test func secondImmediateAcceptanceInSameActorTurnIsRejected() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .gate, .gate,
        ])
        let viewModel = HomeViewModel(home: service)
        await viewModel.handleVisibility(true)
        viewModel.requestAccessibleRefresh()
        #expect(viewModel.refreshTicket == 1, "the first same-turn entry is accepted")
        #expect(viewModel.hasPendingOwnedRequest)
        viewModel.requestAccessibleRefresh()
        #expect(
            viewModel.refreshTicket == 1,
            "the second same-turn immediate entry must be rejected without a new ticket")
        await waitUntil { service.calls == 2 && service.pendingGates == 1 }
        // A pull while the first intent is still owned (read hanging).
        await viewModel.pullToRefresh(interaction: 1)
        #expect(viewModel.refreshTicket == 1)
        #expect(service.calls == 2)
        service.release(.success(Self.snapshot(goodsID: 2)))
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
        #expect(!viewModel.hasPendingOwnedRequest)
    }

    /// R-DB-03: the deadline is anchored at ACCEPTANCE. When the task starts
    /// 250ms late, it must wait only the remaining 50ms — not a fresh 300ms.
    @Test func delayedTaskStartWaitsOnlyRemainingMergeTime() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        // Delayed task start: move the virtual clock WITHOUT letting the
        // enqueued task run first.
        sleeper.bump(ms: 250)
        await sleeper.advance(ms: 0)
        #expect(
            sleeper.requestedDurationsMs == [50],
            "the task must sleep only the remaining time to the deadline")
        await sleeper.advance(ms: 50)
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
        #expect(service.calls == 2)
    }

    /// R-DB-03: a deadline that already passed at task start skips the sleep
    /// entirely and reads after the identity/activity recheck.
    @Test func expiredDeadlineAtTaskStartSkipsSleepEntirely() async {
        let service = ScriptedService(steps: [
            .value(Self.snapshot(goodsID: 1)), .value(Self.snapshot(goodsID: 2)),
        ])
        let viewModel = HomeViewModel(home: service)
        let sleeper = mergeClock(for: viewModel)
        await viewModel.handleVisibility(true)
        viewModel.requestRefresh(1)
        sleeper.bump(ms: 400)
        await sleeper.advance(ms: 0)
        #expect(sleeper.requestedDurationsMs.isEmpty, "no sleep once past the deadline")
        #expect(sleeper.sleepCount == 0)
        await waitUntil { viewModel.state == .ready(Self.snapshot(goodsID: 2)) }
        #expect(service.calls == 2)
    }

}
