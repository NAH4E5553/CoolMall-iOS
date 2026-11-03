import Foundation
import MallCore
import Testing
@testable import AccountFeature

@MainActor struct FootprintViewModelTests {
    private func wait(_ check: () -> Bool) async {
        for _ in 0..<1000 { if check() { return }; await Task.yield() };
        Issue.record("gate did not open")
    }
    @Test func initialErrorEmptySuccessAndFailedRefreshPreserveSnapshot() async {
        let source = FootprintFake(); let model = FootprintViewModel(store: source, pageSize: 2)
        source.failNext = true; await model.refresh(); #expect(!model.loaded);
        #expect(model.error != nil)
        await model.refresh(); #expect(model.loaded); #expect(model.items.isEmpty)
        source.items = FootprintFake.items(1...3); await model.refresh();
        #expect(model.items.map(\.id) == [1, 2]); #expect(model.total == 3)
        source.failNext = true; await model.refresh(); #expect(model.items.map(\.id) == [1, 2]);
        #expect(model.nextOffset == 2); #expect(model.operation == nil)
    }
    @Test func appendFailureRetriesSameOffsetAndAutomaticFailureDoesNotLoop() async {
        let source = FootprintFake(); source.items = FootprintFake.items(1...5);
        let model = FootprintViewModel(store: source, pageSize: 2)
        await model.refresh(); source.failNext = true; await model.loadMore(automatic: true)
        #expect(model.appendError != nil); #expect(model.items.count == 2);
        #expect(model.nextOffset == 2)
        await model.loadMore(automatic: true); #expect(source.offsets == [0, 2])
        await model.loadMore(); #expect(source.offsets == [0, 2, 2]);
        #expect(model.items.map(\.id) == [1, 2, 3, 4])
        await model.loadMore(); #expect(model.items.map(\.id) == [1, 2, 3, 4, 5]);
        #expect(model.nextOffset == nil)
        await model.loadMore(); #expect(source.offsets.count == 4)
    }
    @Test func refreshSupersedesUncooperativeAppendAndRejectsDuplicateTrigger() async {
        let source = FootprintFake(); source.items = FootprintFake.items(1...4);
        let model = FootprintViewModel(store: source, pageSize: 2)
        await model.refresh(); source.holdNext = true
        let old = Task { await model.loadMore() }; await wait { source.gate != nil }
        await model.loadMore(); #expect(source.offsets == [0, 2])
        source.items = FootprintFake.items(10...12); source.revision += 1; await model.refresh()
        source.release(); await old.value
        #expect(model.items.map(\.id) == [10, 11]); #expect(model.operation == nil);
        #expect(model.appendError == nil)
    }
    @Test func changedRevisionDuringAppendRestartsHeadInsteadOfMixingPages() async {
        let source = FootprintFake(); source.items = FootprintFake.items(1...5);
        let model = FootprintViewModel(store: source, pageSize: 2)
        await model.refresh(); source.items = FootprintFake.items(10...14); source.revision += 1
        await model.loadMore(); #expect(source.offsets == [0, 2, 0]);
        #expect(model.items.map(\.id) == [10, 11])
    }
    @Test func clearFailureKeepsHistoryAndSuccessfulClearRejectsLateAppend() async {
        let source = FootprintFake(); source.items = FootprintFake.items(1...4);
        let model = FootprintViewModel(store: source, pageSize: 2)
        await model.refresh(); source.failClear = true; await model.clearHistory();
        #expect(model.items.count == 2); #expect(model.error != nil)
        source.failClear = false; source.holdNext = true; let old = Task { await model.loadMore() };
        await wait { source.gate != nil }
        await model.clearHistory(); source.release(); await old.value
        #expect(model.items.isEmpty); #expect(model.total == 0); #expect(model.nextOffset == nil);
        #expect(model.operation == nil)
    }
    @Test func leavingRejectsLatePageWithoutShowingCancellationFailure() async {
        let source = FootprintFake(); source.items = FootprintFake.items(1...4);
        let model = FootprintViewModel(store: source, pageSize: 2)
        await model.refresh(); source.holdNext = true; let old = Task { await model.loadMore() };
        await wait { source.gate != nil }
        model.stop(); source.release(); await old.value; #expect(model.items.count == 2);
        #expect(model.error == nil); #expect(model.appendError == nil)
    }
    @Test func malformedAndNoProgressPagesDoNotAdvanceOrLoop() async {
        let source = FootprintFake(); source.items = FootprintFake.items(1...5);
        let model = FootprintViewModel(store: source, pageSize: 2)
        await model.refresh();
        source.override = .init(items: [], total: 5, revision: 1, nextOffset: 2)
        await model.loadMore(automatic: true); #expect(model.appendError != nil);
        #expect(model.nextOffset == 2)
        await model.loadMore(automatic: true); #expect(source.offsets == [0, 2])
    }
    @Test func previewReadsOnlyEightAndRejectsResultsAfterLeaving() async {
        let source = FootprintFake(); source.items = FootprintFake.items(1...12)
        let model = FootprintPreviewViewModel(store: source); source.holdNext = true
        let reading = Task { await model.observe() }; await wait { source.gate != nil }
        model.stop(); source.release(); reading.cancel(); await reading.value
        #expect(model.items.isEmpty)
        let resumed = Task { await model.observe() }; await wait { model.loaded }
        #expect(model.items.count == 8); #expect(source.limits.allSatisfy { $0 == 8 });
        resumed.cancel(); await resumed.value
    }
}

@MainActor private final class FootprintFake: FootprintBrowsing {
    nonisolated let scope = FootprintScope(environment: "fake", accountID: nil)
    var items: [FootprintItem] = []
    var revision: UInt64 = 1
    var failNext = false
    var failClear = false
    var holdNext = false
    var gate: CheckedContinuation<FootprintPage, Error>?
    var captured: FootprintPage?
    var offsets: [Int] = []
    var limits: [Int] = []
    var override: FootprintPage?
    static func items(_ range: ClosedRange<Int>) -> [FootprintItem] {
        range.map {
            .init(
                id: Int64($0), title: "商品\($0)", subtitle: nil, imageURL: nil, priceYuan: 1,
                sold: 0, viewedAt: Date(timeIntervalSince1970: Double($0)))
        }
    }
    func page(offset: Int, limit: Int) async throws -> FootprintPage {
        offsets.append(offset); limits.append(limit)
        if failNext { failNext = false; throw FootprintFailure.readFailed }
        let start = min(offset, items.count); let end = min(start + limit, items.count)
        let value =
            override
            ?? FootprintPage(
                items: Array(items[start..<end]), total: items.count, revision: revision,
                nextOffset: end < items.count ? end : nil)
        if holdNext {
            holdNext = false; captured = value;
            return try await withCheckedThrowingContinuation { gate = $0 }
        }
        return value
    }
    func release() {
        gate?.resume(
            returning: captured ?? .init(items: [], total: 0, revision: revision, nextOffset: nil));
        gate = nil
    }
    func changes() async throws -> AsyncStream<UInt64> { AsyncStream { $0.yield(revision) } }
    func clear() async throws {
        if failClear { throw FootprintFailure.writeFailed }; items = []; revision += 1
    }
}
