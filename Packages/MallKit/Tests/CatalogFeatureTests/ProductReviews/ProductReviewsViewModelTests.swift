import Foundation
import MallCore
@testable import CatalogFeature
import Testing

@MainActor
struct ProductReviewsViewModelTests {
    static func review(_ id: Int64, content: String = "评价") -> ProductDetailReview {
        ProductDetailReview(
            id: id, productID: 830001, content: content, starCount: 5,
            nickname: nil, avatarURL: nil, imageURLs: [])
    }
    static func page(_ ids: [Int64], next: Int? = nil) -> ProductReviewPage {
        ProductReviewPage(items: ids.map { review($0) }, nextPage: next)
    }
    @MainActor final class Service: ProductReviewsLoading {
        enum Step {
            case value(ProductReviewPage), fail(ProductDetailLoadFailure), gate(cooperative: Bool)
        }
        var steps: [Step]
        var calls: [(id: Int64, page: Int, size: Int)] = []
        var gates: [Int: CheckedContinuation<ProductReviewPage, Error>] = [:]
        var cancellations: Set<Int> = []
        init(_ steps: [Step]) { self.steps = steps }
        func loadReviews(productID: Int64, page: Int, pageSize: Int) async throws
            -> ProductReviewPage
        {
            let index = calls.count; calls.append((productID, page, pageSize))
            guard !steps.isEmpty else { throw ProductDetailLoadFailure.invalidResponse }
            switch steps.removeFirst() {
            case .value(let result): return result
            case .fail(let failure): throw failure
            case .gate(let cooperative):
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        if cooperative && Task.isCancelled {
                            cancellations.insert(index);
                            continuation.resume(throwing: CancellationError())
                        } else {
                            gates[index] = continuation
                        }
                    }
                } onCancel: {
                    Task { @MainActor in
                        self.cancellations.insert(index)
                        if cooperative {
                            self.gates.removeValue(forKey: index)?.resume(
                                throwing: CancellationError())
                        }
                    }
                }
            }
        }
        func finish(_ index: Int, _ result: Result<ProductReviewPage, any Error>) {
            guard let gate = gates.removeValue(forKey: index) else {
                Issue.record("missing real gate"); return
            }
            gate.resume(with: result)
        }
    }
    func wait(_ condition: () -> Bool) async {
        for _ in 0..<2000 { if condition() { return }; await Task.yield() }
        Issue.record("expected state was not reached")
    }
    func loaded(_ service: Service) async -> ProductReviewsViewModel {
        let vm = ProductReviewsViewModel(productID: 830001, loader: service)
        vm.setActive(true); await vm.loadInitial(); return vm
    }
    @Test func initialFailureEmptyAndRetryAreExplicit() async {
        let service = Service([.fail(.timeout), .value(Self.page([]))])
        let vm = await loaded(service)
        #expect(vm.phase == .failed(.timeout)); #expect(vm.items.isEmpty)
        await vm.loadInitial(); #expect(service.calls.count == 1)
        await vm.retryInitial(); #expect(vm.phase == .ready); #expect(vm.nextPage == nil)
        vm.loadMore(); #expect(service.calls.count == 2)
        #expect(service.calls.allSatisfy { $0.id == 830001 && $0.page == 1 && $0.size == 10 })
    }
    @Test func appendFailureRetriesSamePageAndMergesByIdentity() async {
        let service = Service([
            .value(Self.page([1, 2], next: 2)), .fail(.timeout),
            .value(
                ProductReviewPage(
                    items: [Self.review(2, content: "更新"), Self.review(3)], nextPage: nil)),
        ])
        let vm = await loaded(service); vm.loadMore()
        await wait { vm.appendFailure != nil }
        #expect(vm.nextPage == 2); #expect(vm.items.map(\.id) == [1, 2])
        vm.tailDisappeared(); vm.tailAppeared(); #expect(service.calls.count == 2)
        vm.loadMore(); await wait { vm.operation == nil }
        #expect(vm.items.map(\.id) == [1, 2, 3]); #expect(vm.items[1].content == "更新")
        #expect(service.calls.map(\.page) == [1, 2, 2]); #expect(vm.nextPage == nil)
        vm.loadMore(); #expect(service.calls.count == 3)
    }
    @Test func failedRefreshRetainsThenSuccessReplacesAndResetsCursor() async {
        let service = Service([
            .value(Self.page([1], next: 2)), .fail(.networkUnavailable),
            .value(Self.page([4], next: 2)),
        ])
        let vm = await loaded(service); await vm.refresh()
        #expect(vm.items.map(\.id) == [1]); #expect(vm.refreshFailure == .networkUnavailable);
        #expect(vm.nextPage == 2)
        await vm.refresh(); #expect(vm.items.map(\.id) == [4]); #expect(vm.refreshFailure == nil)
        #expect(service.calls.map(\.page) == [1, 1, 1])
    }
    @Test(arguments: [false, true])
    func refreshActuallyCancelsAppendAndRejectsLateValueOrError(_ oldError: Bool) async {
        let service = Service([
            .value(Self.page([1], next: 2)), .gate(cooperative: false), .value(Self.page([9])),
        ])
        let vm = await loaded(service); vm.loadMore(); await wait { service.gates[1] != nil }
        await vm.refresh(); await wait { service.cancellations.contains(1) }
        #expect(vm.items.map(\.id) == [9]); #expect(vm.nextPage == nil)
        service.finish(
            1,
            oldError
                ? .failure(ProductDetailLoadFailure.timeout) : .success(Self.page([88], next: 3)))
        await wait { service.gates.isEmpty }; for _ in 0..<20 { await Task.yield() }
        #expect(vm.items.map(\.id) == [9]); #expect(vm.appendFailure == nil);
        #expect(vm.refreshFailure == nil)
        #expect(service.calls.map(\.page) == [1, 2, 1]); #expect(service.cancellations == [1])
    }
    @Test func busyTriggersCoalesceAndRefreshWaitsForItsRead() async {
        let service = Service([.value(Self.page([1], next: 2)), .gate(cooperative: true)])
        let vm = await loaded(service)
        let refresh = Task { await vm.refresh() }; await wait { service.gates[1] != nil }
        await vm.refresh(); vm.loadMore(); vm.tailAppeared(); vm.tailAppeared()
        #expect(service.calls.count == 2); #expect(vm.operation == .refresh);
        #expect(vm.items.map(\.id) == [1])
        service.finish(1, .success(Self.page([2]))); await refresh.value
        #expect(vm.items.map(\.id) == [2]); #expect(vm.operation == nil)
    }
    @Test func automaticTailHasOneRequestPerAppearanceAndStopsOnNoProgress() async {
        let service = Service([
            .value(Self.page([1], next: 2)), .value(Self.page([1], next: 3)),
            .value(Self.page([2])),
        ])
        let vm = await loaded(service); vm.tailAppeared(); vm.tailAppeared()
        await wait { vm.operation == nil }; vm.tailAppeared()
        vm.tailDisappeared(); vm.tailAppeared()
        #expect(service.calls.count == 2); #expect(vm.nextPage == 3)
        vm.loadMore(); await wait { vm.operation == nil }
        #expect(service.calls.map(\.page) == [1, 2, 3]); #expect(vm.items.map(\.id) == [1, 2])
    }
    @Test func callerCancellationReallyCancelsInitialTaskAndReturnsIdle() async {
        let service = Service([.gate(cooperative: true)])
        let vm = ProductReviewsViewModel(productID: 830001, loader: service); vm.setActive(true)
        let caller = Task { await vm.loadInitial() }; await wait { service.gates[0] != nil }
        caller.cancel(); await caller.value; await wait { service.cancellations.contains(0) }
        #expect(vm.phase == .idle); #expect(vm.operation == nil);
        #expect(service.cancellations == [0])
    }
    @Test(arguments: [false, true])
    func visibilityCancelsPendingReadAndDropsLateCompletion(_ failure: Bool) async {
        let service = Service([.value(Self.page([1], next: 2)), .gate(cooperative: false)])
        let vm = await loaded(service); vm.loadMore(); await wait { service.gates[1] != nil }
        vm.setActive(false); await wait { service.cancellations.contains(1) }
        service.finish(
            1, failure ? .failure(ProductDetailLoadFailure.timeout) : .success(Self.page([2])))
        for _ in 0..<20 { await Task.yield() }
        #expect(vm.items.map(\.id) == [1]); #expect(vm.appendFailure == nil);
        #expect(vm.nextPage == 2)
        vm.setActive(true); await vm.loadInitial(); #expect(service.calls.count == 2)
    }
    @Test func staleCallerCancellationCannotCancelNewRefresh() async {
        let service = Service([
            .gate(cooperative: false), .value(Self.page([1])), .gate(cooperative: true),
        ])
        let vm = ProductReviewsViewModel(productID: 830001, loader: service); vm.setActive(true)
        let stale = Task { await vm.loadInitial() }; await wait { service.gates[0] != nil }
        vm.setActive(false); vm.setActive(true); await vm.loadInitial()
        let latest = Task { await vm.refresh() }; await wait { service.gates[2] != nil }
        stale.cancel(); service.finish(0, .success(Self.page([99])))
        await stale.value; for _ in 0..<20 { await Task.yield() }
        #expect(vm.operation == .refresh); #expect(!service.cancellations.contains(2))
        service.finish(2, .success(Self.page([3]))); await latest.value
        #expect(vm.items.map(\.id) == [3])
    }
    @Test func returningToTheVisibleTailDoesNotReplayCancelledAppend() async {
        let service = Service([
            .value(Self.page([1], next: 2)), .gate(cooperative: true), .value(Self.page([2])),
        ])
        let vm = await loaded(service)
        vm.tailAppeared(); await wait { service.gates[1] != nil }
        vm.setActive(false); await wait { service.cancellations.contains(1) }
        vm.tailDisappeared(); vm.setActive(true); vm.tailAppeared()
        for _ in 0..<20 { await Task.yield() }
        #expect(service.calls.count == 2); #expect(vm.items.map(\.id) == [1]);
        #expect(vm.nextPage == 2)
        // A fresh active tail exit/entry is a new trigger, not a queued old request.
        vm.tailDisappeared(); vm.tailAppeared(); await wait { vm.operation == nil }
        #expect(service.calls.map(\.page) == [1, 2, 2]); #expect(vm.items.map(\.id) == [1, 2])
    }
    @Test func inactiveRetryDoesNotReplayWhenThePageReturns() async {
        let service = Service([.fail(.timeout), .value(Self.page([2]))])
        let vm = await loaded(service)
        vm.setActive(false); await vm.retryInitial()
        vm.setActive(true); await vm.loadInitial()
        #expect(vm.phase == .failed(.timeout)); #expect(service.calls.count == 1)
        await vm.retryInitial()
        #expect(vm.items.map(\.id) == [2]); #expect(service.calls.count == 2)
    }
    @Test func invalidProductAndForeignResponseNeverCommit() async {
        let service = Service([
            .value(
                ProductReviewPage(
                    items: [
                        ProductDetailReview(
                            id: 1, productID: 2, content: "错商品", starCount: 5, nickname: nil,
                            avatarURL: nil, imageURLs: [])
                    ], nextPage: nil))
        ])
        let invalid = ProductReviewsViewModel(productID: 0, loader: service);
        invalid.setActive(true); await invalid.loadInitial()
        #expect(invalid.phase == .failed(.invalidProductID)); #expect(service.calls.isEmpty)
        let vm = await loaded(service); #expect(vm.phase == .failed(.invalidResponse));
        #expect(vm.items.isEmpty)
    }
}
