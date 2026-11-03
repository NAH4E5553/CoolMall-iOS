import Foundation

public enum PageReadFailure: Error, Equatable, Sendable {
    case invalidConfiguration, invalidResponse, authenticationRequired, networkUnavailable, timeout,
        noProgress
    case httpStatus(Int), businessCode(Int)
}

/// Numbered, server-counted read page. Money/query/authentication remain with each capability.
public struct NumberedPage<Item: Sendable>: Sendable {
    public let items: [Item]
    public let page: Int
    public let size: Int
    public let total: Int64
    public init(items: [Item], page: Int, size: Int, total: Int64) {
        self.items = items; self.page = page; self.size = size; self.total = total
    }
}
public enum PageReadOperation: Equatable, Sendable { case initial, refresh, append }
public struct NumberedPageSnapshot<Item: Sendable>: Sendable {
    public let items: [Item]
    public let total: Int64
    public let nextPage: Int?
    public let hasLoaded: Bool
    public let operation: PageReadOperation?
    public let failure: PageReadFailure?
    public let appendFailure: PageReadFailure?
}

/// Page-instance owner shared by coupon and address consumers. No UI, navigation, credentials,
/// persistence or Observation. Its immutable read closure binds the account/query identity.
@MainActor public final class NumberedPageCoordinator<Item: Identifiable & Sendable>
where Item.ID: Sendable {
    public typealias Snapshot = NumberedPageSnapshot<Item>
    public var onChange: (@MainActor (Snapshot) -> Void)?
    private let read: @Sendable (Int, Int) async throws -> NumberedPage<Item>
    private let pageSize: Int
    private var items: [Item] = []
    private var total: Int64 = 0
    private var nextPage: Int?
    private var hasLoaded = false
    private var operation: PageReadOperation?
    private var failure: PageReadFailure?
    private var appendFailure: PageReadFailure?
    private var active = false
    private var generation: UInt64 = 0
    private var request: Task<Void, Never>?
    private var automaticAppendAllowed = true
    public init(
        pageSize: Int, read: @escaping @Sendable (Int, Int) async throws -> NumberedPage<Item>
    ) {
        self.pageSize = pageSize; self.read = read
    }
    deinit { request?.cancel() }
    public var snapshot: Snapshot {
        Snapshot(
            items: items, total: total, nextPage: nextPage, hasLoaded: hasLoaded,
            operation: operation, failure: failure, appendFailure: appendFailure)
    }
    private func publish() { onChange?(snapshot) }
    public func setActive(_ value: Bool) {
        guard active != value else { return }; active = value
        if !value { cancel(); publish() }
    }
    public func loadInitial() async {
        guard active, !hasLoaded, operation == nil, failure == nil else { return }
        await refresh()
    }
    public func refresh() async {
        guard active, !Task.isCancelled else { return }
        if operation == .refresh || operation == .initial {
            if let request { await wait(request, epoch: generation) }; return
        }
        let task = begin(hasLoaded ? .refresh : .initial, page: 1)
        if let task { await wait(task, epoch: generation) }
    }
    public func retry() {
        guard active, operation == nil else { return }
        _ = begin(hasLoaded ? .refresh : .initial, page: 1)
    }
    public func loadMore(automatic: Bool = false) {
        guard active, hasLoaded, operation == nil, let nextPage,
            !automatic || (automaticAppendAllowed && appendFailure == nil)
        else { return }
        automaticAppendAllowed = false
        _ = begin(.append, page: nextPage)
    }
    /// A persistent short footer does not recursively fetch; a new visible tail cycle can.
    public func tailExited() { if active { automaticAppendAllowed = true } }
    private func cancel() {
        generation &+= 1; request?.cancel(); request = nil; operation = nil
    }
    private func begin(_ kind: PageReadOperation, page: Int) -> Task<Void, Never>? {
        guard (1...100).contains(pageSize), page > 0 else {
            failure = .invalidConfiguration; publish(); return nil
        }
        cancel(); let epoch = generation
        operation = kind; failure = nil; appendFailure = nil
        if kind != .append { automaticAppendAllowed = true }
        let read = read; let size = pageSize
        let task = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                let result = try await read(page, size)
                try Task.checkCancellation()
                try self?.commit(result, requested: page, kind: kind, epoch: epoch)
            } catch {
                self?.fail(error, kind: kind, epoch: epoch, cancelled: Task.isCancelled)
            }
        }
        request = task; publish(); return task
    }
    private func wait(_ task: Task<Void, Never>, epoch: UInt64) async {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: { [weak self] in
            task.cancel()
            Task { @MainActor in
                guard let self, self.generation == epoch else { return }
                self.cancel(); self.publish()
            }
        }
    }
    private func commit(
        _ page: NumberedPage<Item>, requested: Int, kind: PageReadOperation, epoch: UInt64
    ) throws {
        guard active, epoch == generation else { return }
        let offset = Int64(requested - 1).multipliedReportingOverflow(by: Int64(pageSize))
        guard !offset.overflow, page.page == requested, page.size == pageSize,
            page.total >= offset.partialValue, requested < Int.max,
            Int64(page.items.count) == min(Int64(pageSize), page.total - offset.partialValue),
            Set(page.items.map(\.id)).count == page.items.count
        else { throw PageReadFailure.invalidResponse }
        if kind == .append {
            var merged = items
            var positions = Dictionary(
                uniqueKeysWithValues: merged.enumerated().map { ($0.element.id, $0.offset) })
            let count = merged.count
            for item in page.items {
                if let index = positions[item.id] {
                    merged[index] = item
                } else {
                    positions[item.id] = merged.count; merged.append(item)
                }
            }
            guard merged.count > count else { throw PageReadFailure.noProgress }
            items = merged
        } else {
            items = page.items
        }
        let remaining = page.total - offset.partialValue
        nextPage = remaining > Int64(page.items.count) ? requested + 1 : nil
        total = page.total; hasLoaded = true; operation = nil; request = nil; publish()
    }
    private func fail(_ error: any Error, kind: PageReadOperation, epoch: UInt64, cancelled: Bool) {
        guard active, epoch == generation else { return }
        request = nil; operation = nil
        if !cancelled, !(error is CancellationError) {
            let value = (error as? PageReadFailure) ?? .invalidResponse
            if kind == .append { appendFailure = value } else { failure = value }
        }
        publish()
    }
}
