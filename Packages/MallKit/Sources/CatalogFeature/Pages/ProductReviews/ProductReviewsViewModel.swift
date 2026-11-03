import Foundation
import MallCore
import Observation

/// One product/page owns its snapshot and the only cancellable read task.
/// The task captures the loader, not this owner across network suspension.
@MainActor @Observable
final class ProductReviewsViewModel {
    enum Phase: Equatable { case idle, loading, ready, failed(ProductDetailLoadFailure) }
    enum Operation { case initial, refresh, append }
    let productID: Int64
    private let loader: any ProductReviewsLoading
    private(set) var phase: Phase = .idle
    private(set) var items: [ProductDetailReview] = []
    private(set) var nextPage: Int?
    private(set) var operation: Operation?
    private(set) var refreshFailure: ProductDetailLoadFailure?
    private(set) var appendFailure: ProductDetailLoadFailure?
    @ObservationIgnored private var active = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var tailVisible = false
    @ObservationIgnored private var requiresNewTailCycle = false
    @ObservationIgnored private var allowsAutomaticAppend = true

    init(productID: Int64, loader: any ProductReviewsLoading) {
        self.productID = productID; self.loader = loader
    }
    deinit { readTask?.cancel() }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if !value {
            if operation == .append { requiresNewTailCycle = true }
            cancelCurrent(); tailVisible = false
        }
    }
    func loadInitial() async {
        guard active, !Task.isCancelled, phase == .idle, operation == nil else { return }
        if let read = begin(.initial, page: 1) { await wait(read) }
    }
    func retryInitial() async {
        guard active, !Task.isCancelled, case .failed = phase else { return }
        phase = .idle; await loadInitial()
    }
    func refresh() async {
        guard active, !Task.isCancelled, phase == .ready, operation != .refresh else { return }
        // A refresh supersedes append, but preserves the committed snapshot.
        if let read = begin(.refresh, page: 1) { await wait(read) }
    }
    func loadMore() { append(automatic: false) }
    func tailAppeared() {
        guard !tailVisible else { return }
        tailVisible = true
        guard !requiresNewTailCycle else { return }
        append(automatic: true)
    }
    func tailDisappeared() {
        tailVisible = false
        // Removal while inactive does not turn a cancelled request into a new intent.
        if active { requiresNewTailCycle = false }
    }
    private func append(automatic: Bool) {
        guard active, phase == .ready, operation == nil, let nextPage else { return }
        guard !automatic || (allowsAutomaticAppend && appendFailure == nil) else { return }
        if !automatic { requiresNewTailCycle = false }
        _ = begin(.append, page: nextPage)
    }
    private struct Read { let generation: Int; let task: Task<Void, Never> }
    private func begin(_ kind: Operation, page: Int) -> Read? {
        guard productID > 0 else { phase = .failed(.invalidProductID); return nil }
        cancelCurrent()
        generation += 1
        let identity = generation
        operation = kind
        if kind == .initial { phase = .loading }
        if kind == .refresh { refreshFailure = nil; requiresNewTailCycle = false }
        appendFailure = nil
        let loader = loader; let productID = productID
        let task = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                let result = try await loader.loadReviews(
                    productID: productID, page: page, pageSize: 10)
                try Task.checkCancellation()
                self?.complete(result, kind: kind, page: page, identity: identity)
            } catch {
                self?.fail(error, kind: kind, identity: identity, cancelled: Task.isCancelled)
            }
        }
        readTask = task
        return Read(generation: identity, task: task)
    }
    private func wait(_ read: Read) async {
        await withTaskCancellationHandler {
            await read.task.value
        } onCancel: { [weak self] in
            read.task.cancel()
            Task { @MainActor in
                guard let self, self.generation == read.generation else { return }
                self.cancelCurrent()
            }
        }
    }
    private func complete(_ result: ProductReviewPage, kind: Operation, page: Int, identity: Int) {
        guard active, generation == identity else { return }
        guard
            result.items.allSatisfy({
                $0.id > 0 && $0.productID == productID && (0...5).contains($0.starCount)
            }),
            Set(result.items.map(\.id)).count == result.items.count,
            result.nextPage == nil || result.nextPage == page + 1
        else {
            fail(
                ProductDetailLoadFailure.invalidResponse, kind: kind, identity: identity,
                cancelled: false)
            return
        }
        if kind == .append {
            var merged = items
            var positions = Dictionary(
                uniqueKeysWithValues: merged.enumerated().map { ($0.element.id, $0.offset) })
            let oldCount = merged.count
            for item in result.items {
                if let index = positions[item.id] {
                    merged[index] = item
                } else {
                    positions[item.id] = merged.count; merged.append(item)
                }
            }
            items = merged
            if items.count == oldCount { allowsAutomaticAppend = false }
        } else {
            items = result.items
            allowsAutomaticAppend = true
        }
        nextPage = result.nextPage; phase = .ready; operation = nil; readTask = nil
    }
    private func fail(_ error: any Error, kind: Operation, identity: Int, cancelled: Bool) {
        guard active, generation == identity else { return }
        operation = nil; readTask = nil
        if cancelled || error is CancellationError {
            if kind == .initial { phase = .idle }
            return
        }
        let failure = (error as? ProductDetailLoadFailure) ?? .invalidResponse
        switch kind {
        case .initial: phase = .failed(failure)
        case .refresh: refreshFailure = failure
        case .append: appendFailure = failure
        }
    }
    private func cancelCurrent() {
        generation += 1; readTask?.cancel(); readTask = nil; operation = nil
        if phase == .loading { phase = .idle }
    }
}
