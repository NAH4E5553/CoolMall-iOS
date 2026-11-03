import Foundation
import MallCore
@testable import CatalogFeature
import Testing

/// CATEGORY-01 page-model contract: loading/success/empty/failure/retry, one
/// cancellable read owned by the view task, stale value/error isolation,
/// retained state across tab switches, and the left/right selection + scroll
/// intent with its loop guard. Gate/continuation controlled; no sleeps.
@MainActor
struct CategoryViewModelTests {
    @MainActor
    final class ScriptedService: CategoryLoading {
        enum Step {
            case value([CategoryNode])
            case failure(CategoryLoadFailure)
            case plainFailure
            case gate
            case never
        }

        private var steps: [Step]
        private(set) var calls = 0
        private var gated: [CheckedContinuation<Result<[CategoryNode], Error>, Never>] = []

        init(steps: [Step]) {
            self.steps = steps
        }

        var pendingGates: Int { gated.count }

        func loadCategories() async throws -> [CategoryNode] {
            calls += 1
            let step = steps.isEmpty ? .never : steps.removeFirst()
            switch step {
            case .value(let categories): return categories
            case .failure(let failure): throw failure
            case .plainFailure: throw TestFailure()
            case .gate:
                return try await withCheckedContinuation { continuation in
                    gated.append(continuation)
                }.get()
            case .never:
                while true {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            }
        }

        func release(_ result: Result<[CategoryNode], Error>) {
            guard !gated.isEmpty else { return }
            gated.removeFirst().resume(returning: result)
        }

        func releaseLatest(_ result: Result<[CategoryNode], Error>) {
            guard !gated.isEmpty else { return }
            gated.removeLast().resume(returning: result)
        }
    }

    struct TestFailure: Error {}

    static func category(
        _ id: Int64, _ name: String, _ parent: Int64?, _ sortNum: Int
    ) -> CategoryNode {
        CategoryNode(id: id, name: name, parentID: parent, sortNum: sortNum, imageURL: nil)
    }

    static let tree: [CategoryNode] = [
        category(2, "平板", nil, 2),
        category(1, "手机", nil, 1),
        category(12, "子2", 1, 2),
        category(11, "子1", 1, 1),
    ]

    static let otherTree: [CategoryNode] = [
        category(3, "穿戴", nil, 3),
        category(1, "手机", nil, 1),
    ]

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

    // MARK: load states

    @Test func firstLoadCommitsReadyAndSelectsFirstRoot() async {
        let service = ScriptedService(steps: [.value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        #expect(service.calls == 1)
        guard case .ready(let snapshot) = viewModel.state else {
            Issue.record("expected ready, got \(viewModel.state)")
            return
        }
        #expect(snapshot.groups.map(\.root.id) == [1, 2])
        #expect(snapshot.groups[0].children.map(\.id) == [11, 12])
        #expect(viewModel.selectedRootID == 1)
        #expect(viewModel.scrollRequest == nil)
    }

    @Test func emptyListCommitsEmpty() async {
        let service = ScriptedService(steps: [.value([])])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        #expect(viewModel.state == .empty)
        #expect(viewModel.selectedRootID == nil)
    }

    @Test func failureCommitsFailedAndRetrySucceeds() async {
        let service = ScriptedService(steps: [.failure(.timeout), .value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        #expect(viewModel.state == .failed(.timeout))
        viewModel.requestRetry()
        #expect(viewModel.state == .loading)
        await viewModel.drive(active: true, ticket: viewModel.readTicket)
        #expect(service.calls == 2)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after retry")
            return
        }
        #expect(viewModel.selectedRootID == 1)
    }

    @Test func retryFromEmptyCanSucceed() async {
        let service = ScriptedService(steps: [.value([]), .value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        #expect(viewModel.state == .empty)
        viewModel.requestRetry()
        await viewModel.drive(active: true, ticket: viewModel.readTicket)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready after empty retry")
            return
        }
    }

    @Test func loadingRejectsSecondRetryAndReadyRejectsRetry() async {
        let service = ScriptedService(steps: [.gate, .value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        let task = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        let ticket = viewModel.readTicket
        viewModel.requestRetry()
        #expect(viewModel.readTicket == ticket)
        #expect(service.calls == 1)
        service.release(.success(Self.tree))
        await task.value
        guard case .ready = viewModel.state else { return }
        viewModel.requestRetry()
        #expect(viewModel.readTicket == ticket)
        #expect(service.calls == 1)
    }

    @Test func plainErrorMapsToNetworkUnavailable() async {
        let service = ScriptedService(steps: [.plainFailure])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        #expect(viewModel.state == .failed(.networkUnavailable))
    }

    // MARK: cancellation / stale isolation / retention

    @Test func visibilityLossRestoresIdleAndLateValueIsIgnored() async {
        let service = ScriptedService(steps: [.gate])
        let viewModel = CategoryViewModel(categories: service)
        let task = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        await viewModel.drive(active: false, ticket: 0)
        #expect(viewModel.state == .idle)
        service.release(.success(Self.tree))
        await task.value
        #expect(viewModel.state == .idle)
    }

    @Test func returnAfterSuspensionReReadsOnceAndStaleCompletionLoses() async {
        let service = ScriptedService(steps: [.gate, .gate])
        let viewModel = CategoryViewModel(categories: service)
        let first = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        await viewModel.drive(active: false, ticket: 0)
        let second = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 2 && service.pendingGates == 2 }
        service.releaseLatest(.success(Self.otherTree))
        await second.value
        guard case .ready(let committed) = viewModel.state else {
            Issue.record("expected ready from the newer read")
            return
        }
        #expect(committed.groups.map(\.root.id) == [1, 3])
        service.release(.success(Self.tree))
        await first.value
        #expect(viewModel.state == .ready(committed))
    }

    @Test func staleFailureCannotReplaceCommittedEmpty() async {
        let service = ScriptedService(steps: [.gate, .gate])
        let viewModel = CategoryViewModel(categories: service)
        let first = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        await viewModel.drive(active: false, ticket: 0)
        let second = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 2 && service.pendingGates == 2 }
        service.releaseLatest(.success([]))
        await second.value
        #expect(viewModel.state == .empty)
        service.release(.failure(CategoryLoadFailure.httpStatus(500)))
        await first.value
        #expect(viewModel.state == .empty)
    }

    @Test func readySnapshotAndSelectionRetainedAcrossVisibilityWithoutReread() async {
        let service = ScriptedService(steps: [.value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        viewModel.selectRoot(2)
        for _ in 0..<2 {
            await viewModel.drive(active: false, ticket: 0)
            await viewModel.drive(active: true, ticket: 0)
        }
        #expect(service.calls == 1)
        #expect(viewModel.selectedRootID == 2)
        guard case .ready = viewModel.state else {
            Issue.record("ready must be retained")
            return
        }
    }

    @Test func emptyAndFailedStatesAreRetainedWithoutAutoRetry() async {
        let emptyService = ScriptedService(steps: [.value([])])
        let emptyViewModel = CategoryViewModel(categories: emptyService)
        await emptyViewModel.drive(active: true, ticket: 0)
        await emptyViewModel.drive(active: false, ticket: 0)
        await emptyViewModel.drive(active: true, ticket: 0)
        #expect(emptyViewModel.state == .empty)
        #expect(emptyService.calls == 1)

        let failedService = ScriptedService(steps: [.failure(.networkUnavailable)])
        let failedViewModel = CategoryViewModel(categories: failedService)
        await failedViewModel.drive(active: true, ticket: 0)
        await failedViewModel.drive(active: false, ticket: 0)
        await failedViewModel.drive(active: true, ticket: 0)
        #expect(failedViewModel.state == .failed(.networkUnavailable))
        #expect(failedService.calls == 1)
    }

    @Test func callerCancellationOfFirstLoadRestoresIdleAndRejectsLateValue() async {
        let service = ScriptedService(steps: [.gate])
        let viewModel = CategoryViewModel(categories: service)
        let task = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        task.cancel()
        service.release(.success(Self.tree))
        await task.value
        await waitUntil { service.pendingGates == 0 }
        #expect(viewModel.state == .idle, "a cancelled caller's late value must not commit")
    }

    @Test func neverReturningServiceSuspendsAndCancellationRestoresIdle() async {
        let service = ScriptedService(steps: [.never])
        let viewModel = CategoryViewModel(categories: service)
        let task = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 1 }
        #expect(viewModel.state == .loading)
        task.cancel()
        await task.value
        #expect(viewModel.state == .idle)
    }

    @Test func pageTeardownInvalidatesInFlightRead() async {
        let service = ScriptedService(steps: [.gate])
        let viewModel = CategoryViewModel(categories: service)
        let task = Task { await viewModel.drive(active: true, ticket: 0) }
        await waitUntil { service.calls == 1 && service.pendingGates == 1 }
        viewModel.pageTeardown()
        #expect(viewModel.state == .idle)
        service.release(.success(Self.tree))
        await task.value
        #expect(viewModel.state == .idle)
    }

    // MARK: selection and scroll linkage

    @Test func leftTapChangesSelectionAndBumpsOneScrollRequest() async {
        let service = ScriptedService(steps: [.value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        viewModel.selectRoot(2)
        #expect(viewModel.selectedRootID == 2)
        let firstToken = viewModel.scrollRequest?.token
        #expect(viewModel.scrollRequest?.rootID == 2)
        viewModel.selectRoot(2)
        #expect(viewModel.scrollRequest?.token == firstToken, "same root is a no-op")
        viewModel.selectRoot(999)
        #expect(viewModel.selectedRootID == 2)
        #expect(viewModel.scrollRequest?.token == firstToken)
    }

    @Test func rightScrollChangesSelectionWithoutRequestingAScroll() async {
        let service = ScriptedService(steps: [.value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        viewModel.selectFromScroll(2)
        #expect(viewModel.selectedRootID == 2)
        #expect(viewModel.scrollRequest == nil)
        viewModel.selectFromScroll(999)
        #expect(viewModel.selectedRootID == 2)
    }

    @Test func programmaticScrollGuardIgnoresIntermediatesUntilTargetThenSyncs() async {
        let service = ScriptedService(steps: [.value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        viewModel.selectRoot(2)
        let token = viewModel.scrollRequest?.token
        // Intermediate observation during the left-tap scroll: no bounce back.
        viewModel.selectFromScroll(1)
        #expect(viewModel.selectedRootID == 2)
        #expect(viewModel.scrollRequest?.token == token)
        // The target observation completes the guard (selection stays 2).
        viewModel.selectFromScroll(2)
        #expect(viewModel.selectedRootID == 2)
        // A later real scroll observation now drives the selection.
        viewModel.selectFromScroll(1)
        #expect(viewModel.selectedRootID == 1)
    }

    @Test func userDragInterruptsProgrammaticGuard() async {
        let service = ScriptedService(steps: [.value(Self.tree)])
        let viewModel = CategoryViewModel(categories: service)
        await viewModel.drive(active: true, ticket: 0)
        viewModel.selectRoot(2)
        viewModel.userInterruptedProgrammaticScroll()
        viewModel.selectFromScroll(1)
        #expect(viewModel.selectedRootID == 1)
    }
}
