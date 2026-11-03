import Foundation
import MallCore
import Observation

@MainActor @Observable final class FootprintViewModel {
    enum Operation { case initial, refresh, append, clear }
    private let store: any FootprintBrowsing
    private let pageSize: Int
    private(set) var items: [FootprintItem] = []
    private(set) var total = 0
    private(set) var revision: UInt64?
    private(set) var nextOffset: Int?
    private(set) var operation: Operation?
    private(set) var error: String?
    private(set) var appendError: String?
    private(set) var loaded = false
    private var generation = 0
    private var request: Task<FootprintPage, Error>?
    private var command: Task<Void, Never>?
    private var attemptedTail: Int?
    init(store: any FootprintBrowsing, pageSize: Int = 20) {
        self.store = store; self.pageSize = pageSize
    }
    func observe() async {
        do {
            let stream = try await store.changes()
            for await value in stream {
                guard !Task.isCancelled else { return }
                if value != revision, operation != .clear { await refresh() }
            }
        } catch { if !Task.isCancelled { self.error = "足迹读取失败，请重试" } }
    }
    func refresh() async {
        generation += 1; let epoch = generation
        request?.cancel(); operation = loaded ? .refresh : .initial; error = nil; appendError = nil
        let task = Task { [store, pageSize] in try await store.page(offset: 0, limit: pageSize) };
        request = task
        defer { if epoch == generation { request = nil; operation = nil } }
        do {
            let page = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation(); guard epoch == generation else { return }
            guard Self.valid(page, offset: 0), page.items.count <= pageSize else {
                throw FootprintFailure.invalidPage
            }
            items = page.items; total = page.total; revision = page.revision;
            nextOffset = page.nextOffset; loaded = true; attemptedTail = nil
        } catch {
            if epoch == generation, !Task.isCancelled, !(error is CancellationError) {
                self.error = "足迹刷新失败，原记录保留，请重试"
            }
        }
    }
    func loadMore(automatic: Bool = false) async {
        guard loaded, operation == nil, let offset = nextOffset else { return }
        if automatic, attemptedTail == offset { return }
        attemptedTail = offset; generation += 1; let epoch = generation
        operation = .append; appendError = nil
        let task = Task { [store, pageSize] in try await store.page(offset: offset, limit: pageSize)
        }; request = task
        defer { if epoch == generation { request = nil; operation = nil } }
        do {
            let page = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation(); guard epoch == generation else { return }
            if page.revision != revision { operation = nil; await refresh(); return }
            guard Self.valid(page, offset: offset), page.items.count <= pageSize,
                !page.items.isEmpty, page.nextOffset.map { $0 > offset } ?? true
            else { throw FootprintFailure.invalidPage }
            let ids = Set(items.map(\.id));
            guard page.items.contains(where: { !ids.contains($0.id) }) else {
                throw FootprintFailure.invalidPage
            }
            for item in page.items {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = item
                } else {
                    items.append(item)
                }
            }
            total = page.total; nextOffset = page.nextOffset
        } catch {
            if epoch == generation, !Task.isCancelled, !(error is CancellationError) {
                appendError = "加载更多失败，点击重试"
            }
        }
    }
    func retry() { command?.cancel(); command = Task { [weak self] in await self?.refresh() } }
    func append() { command?.cancel(); command = Task { [weak self] in await self?.loadMore() } }
    func clear() {
        guard operation != .clear else { return }
        command?.cancel(); command = Task { [weak self] in await self?.clearHistory() }
    }
    func clearHistory() async {
        guard operation != .clear else { return }
        generation += 1; let epoch = generation; request?.cancel(); operation = .clear; error = nil
        do {
            try await store.clear(); try Task.checkCancellation()
            guard epoch == generation else { return }
            operation = nil; await refresh()
        } catch {
            guard epoch == generation else { return }; operation = nil
            if !Task.isCancelled, !(error is CancellationError) { self.error = "清空失败，原足迹保留，请重试" }
        }
    }
    func stop() {
        generation += 1; request?.cancel(); request = nil; command?.cancel(); command = nil;
        operation = nil
    }
    private static func valid(_ page: FootprintPage, offset: Int) -> Bool {
        guard offset >= 0, page.total >= offset, page.items.count <= page.total - offset,
            Set(page.items.map(\.id)).count == page.items.count,
            page.items.allSatisfy({ $0.id > 0 })
        else { return false }
        let end = offset + page.items.count
        guard end == page.total || !page.items.isEmpty else { return false }
        return page.nextOffset == (end < page.total ? end : nil)
    }
}
