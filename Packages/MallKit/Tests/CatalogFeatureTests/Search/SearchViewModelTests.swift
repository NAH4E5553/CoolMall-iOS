import Foundation
import MallCore
import Testing
@testable import CatalogFeature

@MainActor struct SearchViewModelTests {
    @Test func whitespaceIsIgnoredAndPendingDoubleSubmitHasOneHistoryCommand() async {
        let history = SearchHistoryFake(hold: true)
        let model = SearchViewModel(loader: SearchKeywordsFake(), history: history)
        model.activate(true)
        #expect(await model.submit(" \n") == nil)
        let first = Task { await model.submit(" 手机 ") }
        await history.waitForRecord()
        #expect(await model.submit("手机") == nil)
        await history.finish()
        #expect(await first.value?.keyword == "手机")
        #expect(await history.recorded == ["手机"])
        model.activate(false)
    }
    @Test func leavingDuringHistorySaveCannotNavigateAndSaveFailureStillSearches() async {
        let history = SearchHistoryFake(hold: true)
        let model = SearchViewModel(loader: SearchKeywordsFake(), history: history)
        model.activate(true)
        let first = Task { await model.submit("旧词") }
        await history.waitForRecord(); model.activate(false); await history.finish()
        #expect(await first.value == nil)
        let failing = SearchHistoryFake(fail: true)
        let next = SearchViewModel(loader: SearchKeywordsFake(), history: failing)
        next.activate(true)
        let result = await next.submit("仍能搜索")
        #expect(result?.keyword == "仍能搜索" && result?.historyFailed == true)
        next.activate(false)
    }
    @Test func cancelledSubmitWhoseStoreIgnoresCancellationReleasesSingleFlight() async {
        let history = SearchHistoryFake(hold: true)
        let model = SearchViewModel(loader: SearchKeywordsFake(), history: history)
        model.activate(true)
        let task = Task { await model.submit("取消") }
        await history.waitForRecord(); task.cancel(); await history.finish()
        #expect(await task.value?.keyword == nil); #expect(!model.submitting)
        model.activate(false)
    }
    @Test func scopeChangeKeepsDraftButRejectsOldHistoryAndSubmission() async {
        let history = SearchHistoryFake(hold: true)
        let model = SearchViewModel(loader: SearchKeywordsFake(), history: history)
        model.draft = "原草稿"; model.activate(true)
        let submit = Task { await model.submit("游客词") }; await history.waitForRecord()
        model.updateHistory(EmptyAccountHistory()); await history.finish()
        #expect(await submit.value?.keyword == nil)
        for _ in 0..<100 { await Task.yield() }
        #expect(model.history.isEmpty && model.draft == "原草稿" && !model.submitting)
        model.activate(false)
    }
    @Test func hotFailureDoesNotBlockInputOrHistoryAndClearFailurePreservesSnapshot() async {
        let history = SearchHistoryFake(fail: true)
        let model = SearchViewModel(loader: SearchKeywordsFake(fail: true), history: history)
        model.activate(true)
        for _ in 0..<100 {
            if model.keywordFailed && !model.history.isEmpty { break }; await Task.yield()
        }
        #expect(model.keywordFailed); #expect(model.history == ["已有词"])
        await model.clear(); #expect(model.notice != nil); #expect(model.history == ["已有词"])
        #expect(await model.submit("新词")?.keyword == "新词")
        model.activate(false)
    }
}
private struct SearchKeywordsFake: SearchKeywordsLoading {
    var fail = false
    func loadSearchKeywords() throws -> [String] {
        if fail { throw PageReadFailure.timeout }; return ["手机"]
    }
}
actor SearchHistoryFake: SearchHistoryStoring {
    nonisolated let scope = SearchHistoryScope(environment: "test", accountID: nil)
    private let hold: Bool
    private let fail: Bool
    var recorded: [String] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private var recordGate: CheckedContinuation<Void, Never>?
    init(hold: Bool = false, fail: Bool = false) { self.hold = hold; self.fail = fail }
    func record(_ keyword: String) async throws {
        recorded.append(keyword)
        if hold {
            await withCheckedContinuation {
                recordGate = $0; waiter?.resume(); waiter = nil
            }
        }
        if fail { throw SearchHistoryFailure.writeFailed }
    }
    func waitForRecord() async {
        if recordGate != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() { recordGate?.resume(); recordGate = nil }
    func changes() -> AsyncStream<SearchHistorySnapshot> {
        AsyncStream {
            $0.yield(.init(keywords: ["已有词"], revision: 1)); $0.finish()
        }
    }
    func clear() throws { if fail { throw SearchHistoryFailure.writeFailed } }
}

private struct EmptyAccountHistory: SearchHistoryStoring {
    let scope = SearchHistoryScope(environment: "test", accountID: "a")
    func record(_ keyword: String) {}
    func clear() {}
    func changes() -> AsyncStream<SearchHistorySnapshot> {
        AsyncStream {
            $0.yield(.init(keywords: [], revision: 0)); $0.finish()
        }
    }
}
