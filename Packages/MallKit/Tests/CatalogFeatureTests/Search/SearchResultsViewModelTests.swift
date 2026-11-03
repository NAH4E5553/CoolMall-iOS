import Foundation
import MallCore
import Testing
@testable import CatalogFeature

@MainActor struct SearchResultsViewModelTests {
    @Test func categoryEntryKeepsIDsThroughSortPagingAndClearedKeywordWithoutHistory() async {
        let loader = SearchPageGate(); let history = SearchHistoryFake()
        let model = SearchResultsViewModel(
            keyword: "", loader: loader, categories: SearchCategoryFake(), history: history,
            categoryIDs: [801008])
        let initial = Task { await model.activate(true) }; await loader.wait(1)
        await loader.succeed(0, total: 11); await initial.value
        model.more(); await loader.wait(2); await loader.succeed(1, id: 11, total: 11)
        for _ in 0..<1000 { if model.state.operation == nil { break }; await Task.yield() }
        model.sort("price"); await loader.wait(3); await loader.succeed(2)
        for _ in 0..<1000 { if model.state.operation == nil { break }; await Task.yield() }
        model.draft = " "; await model.submitKeyword()
        #expect(await history.recorded.isEmpty)
        let queries = await loader.queries
        #expect(queries.count == 3)
        #expect(
            queries.allSatisfy {
                $0.0.categoryIDs == [801008] && $0.0.keyword.isEmpty && !$0.0.featuredOnly
            })
        #expect(queries.map { $0.1 } == [1, 2, 1])
        model.stop()
    }
    private func model(_ loader: SearchPageGate) -> SearchResultsViewModel {
        SearchResultsViewModel(
            keyword: "手机", loader: loader, categories: SearchCategoryFake(),
            history: SearchHistoryFake())
    }
    @Test func oldQuerySuccessCannotOverwriteNewSortAndLayoutDoesNotRead() async {
        let loader = SearchPageGate(); let model = model(loader)
        let initial = Task { await model.activate(true) }
        await loader.wait(1)
        model.scrollAnchor = 7
        let originalViewport = model.resultsRevision
        model.sort("sales"); await loader.wait(2)
        #expect(model.query.sort == .salesAscending)
        #expect(model.resultsRevision != originalViewport && model.scrollAnchor == nil)
        await loader.succeed(1, id: 2); await loader.succeed(0, id: 1); await initial.value
        await settle(model, id: 2)
        #expect(model.state.items.map(\.id) == [2])
        let sortedViewport = model.resultsRevision
        model.scrollAnchor = 2; model.toggleLayout()
        #expect(!model.grid && model.scrollAnchor == 2 && model.resultsRevision == sortedViewport)
        model.stop(); await model.activate(true)
        #expect(model.scrollAnchor == 2 && model.resultsRevision == sortedViewport)
        #expect(await loader.queries.count == 2)
        model.stop()
    }
    @Test func oldFailureAndCancelledPageCannotBecomeNewQueryError() async {
        let loader = SearchPageGate(); let model = model(loader)
        let initial = Task { await model.activate(true) }; await loader.wait(1)
        model.sort("price"); await loader.wait(2)
        await loader.fail(0); await loader.succeed(1, id: 3); await initial.value
        await settle(model, id: 3); #expect(model.state.failure == nil)
        model.stop(); await model.activate(true)
        #expect(await loader.queries.count == 2)
    }
    @Test func sortingCyclesAndPreservesKeywordFiltersUsesPageOne() async {
        let loader = SearchPageGate(); let model = model(loader)
        let initial = Task { await model.activate(true) }; await loader.wait(1);
        await loader.succeed(0); await initial.value
        model.showFilters(); model.minimumDraft = "299.15"; model.maximumDraft = "999";
        model.selectedCategories = [3, 2]
        model.applyFilters(); await loader.wait(2); await loader.succeed(1)
        model.sort("sales"); await loader.wait(3); await loader.succeed(2)
        model.sort("sales"); await loader.wait(4); await loader.succeed(3)
        model.sort("sales"); await loader.wait(5); await loader.succeed(4)
        let values = await loader.queries
        #expect(
            values.map { $0.0.sort } == [
                .comprehensive, .comprehensive, .salesAscending, .salesDescending, .comprehensive,
            ])
        #expect(values.allSatisfy { $0.1 == 1 && $0.2 == 10 })
        #expect(values.last?.0.categoryIDs == [2, 3]);
        #expect(values.last?.0.minimumPrice == Decimal(string: "299.15"))
        model.stop()
    }
    @Test func resetAndCloseOnlyDiscardDraftAndNoChangeConfirmDoesNotRead() async {
        let loader = SearchPageGate(); let model = model(loader)
        let initial = Task { await model.activate(true) }; await loader.wait(1);
        await loader.succeed(0); await initial.value
        model.showFilters(); model.minimumDraft = "500"; model.selectedCategories = [2]
        model.dismissFilters(); #expect(model.query.minimumPrice == nil)
        model.showFilters(); #expect(model.minimumDraft == "" && model.selectedCategories.isEmpty)
        model.minimumDraft = "5"; model.resetFilters(); model.applyFilters()
        #expect(!model.filterVisible); #expect(await loader.queries.count == 1)
        model.stop()
    }
    @Test func invalidPricesKeepModalAndNeverRequestAndDecimalBoundsAreExact() async {
        let loader = SearchPageGate(); let model = model(loader)
        let initial = Task { await model.activate(true) }; await loader.wait(1);
        await loader.succeed(0); await initial.value
        model.showFilters()
        for text in ["-1", "1.234", "1e4", "NaN", "abc", ".", "1..2"] {
            model.minimumDraft = text; model.applyFilters()
            #expect(model.filterVisible && model.filterError != nil)
        }
        model.minimumDraft = "10"; model.maximumDraft = "9"; model.applyFilters()
        #expect(model.filterError == "最低价不能高于最高价"); #expect(await loader.queries.count == 1)
        model.minimumDraft = "0"; model.maximumDraft = "0.01"; model.applyFilters();
        await loader.wait(2)
        let observedQueries = await loader.queries
        let next = observedQueries[1].0
        #expect(next.minimumPrice == 0 && next.maximumPrice == Decimal(string: "0.01"))
        await loader.succeed(1); model.stop()
    }
    @Test func changingKeywordUpdatesSameOwnerAndRecordsHistoryWithoutLosingFilters() async {
        let loader = SearchPageGate(); let history = SearchHistoryFake()
        let model = SearchResultsViewModel(
            keyword: "A", loader: loader, categories: SearchCategoryFake(), history: history)
        let initial = Task { await model.activate(true) }; await loader.wait(1);
        await loader.succeed(0); await initial.value
        model.draft = " \n"; await model.submitKeyword(); #expect(await history.recorded.isEmpty)
        model.draft = " B "; await model.submitKeyword(); await loader.wait(2)
        #expect(model.query.keyword == "B"); #expect(await history.recorded == ["B"])
        await loader.succeed(1); model.stop()
    }
    @Test func refreshFailureKeepsProductsAndAppendFailureRetriesSamePage() async {
        let loader = SearchPageGate(); let model = model(loader)
        let initial = Task { await model.activate(true) }; await loader.wait(1)
        await loader.succeed(0, total: 11); await initial.value
        model.more(); await loader.wait(2); await loader.fail(1)
        for _ in 0..<100 { if model.state.appendFailure != nil { break }; await Task.yield() }
        #expect(model.state.items.count == 10)
        model.more(); await loader.wait(3); let appendQueries = await loader.queries
        #expect(appendQueries[2].1 == 2)
        await loader.succeed(2, id: 11, total: 11)
        for _ in 0..<1000 { if model.state.items.count == 11 { break }; await Task.yield() }
        let refresh = Task { await model.refresh() }; await loader.wait(4); await loader.fail(3);
        await refresh.value
        #expect(model.state.items.count == 11); #expect(model.state.failure == .timeout)
        model.stop()
    }
    @Test func refreshCallbackCancellationKeepsAcceptedReadButLeavingCancelsIt() async {
        let loader = SearchPageGate(); let model = model(loader)
        let initial = Task { await model.activate(true) }; await loader.wait(1)
        await loader.succeed(0); await initial.value
        let refresh = Task { await model.refresh() }; await loader.wait(2)
        refresh.cancel(); await loader.succeed(1, id: 21); await refresh.value
        await settle(model, id: 21)
        #expect(model.state.items.map(\.id) == [21])
        #expect(model.state.failure == nil && model.state.operation == nil)
        let cancelled = Task { await model.refresh() }; cancelled.cancel(); await cancelled.value
        #expect(await loader.queries.count == 2)
        let leaving = Task { await model.refresh() }; await loader.wait(3)
        model.stop(); await loader.succeed(2, id: 31); await leaving.value
        #expect(model.state.items.map(\.id) == [21])
        #expect(model.state.failure == nil && model.state.operation == nil)
        await model.activate(true)
        let replacing = Task { await model.refresh() }; await loader.wait(4)
        model.sort("price"); await loader.wait(5)
        await loader.succeed(4, id: 41); await loader.succeed(3, id: 51); await replacing.value
        await settle(model, id: 41)
        #expect(model.state.items.map(\.id) == [41] && model.query.sort == .priceAscending)
        #expect(model.state.failure == nil && model.state.operation == nil)
        model.stop()
    }
    @Test func changingHistoryScopePreservesQueryLayoutPagesAndRejectsOldWriteReceipt() async {
        let loader = SearchPageGate(); let guest = SearchHistoryFake(hold: true)
        let model = SearchResultsViewModel(
            keyword: "A", loader: loader, categories: SearchCategoryFake(), history: guest)
        let initial = Task { await model.activate(true) }; await loader.wait(1);
        await loader.succeed(0); await initial.value
        model.toggleLayout(); model.scrollAnchor = 1
        model.draft = "B"
        let submit = Task { await model.submitKeyword() }; await guest.waitForRecord()
        model.updateHistory(AccountSearchHistory())
        await guest.finish(); await submit.value
        #expect(model.query.keyword == "A" && !model.grid && model.scrollAnchor == 1)
        #expect(model.state.items.map(\.id) == [1]); #expect(!model.submitting)
        #expect(await loader.queries.count == 1)
        model.stop()
    }
    @Test func cancelledRecordCannotLeaveResultsSubmitLockedOrChangeKeyword() async {
        let loader = SearchPageGate(); let history = SearchHistoryFake(hold: true)
        let model = SearchResultsViewModel(
            keyword: "A", loader: loader, categories: SearchCategoryFake(), history: history)
        let initial = Task { await model.activate(true) }; await loader.wait(1);
        await loader.succeed(0); await initial.value
        model.draft = "B"; let submit = Task { await model.submitKeyword() }
        await history.waitForRecord(); submit.cancel(); await history.finish(); await submit.value
        #expect(!model.submitting); #expect(model.query.keyword == "A")
        model.showFilters(); model.minimumDraft = "123456789012345678901234567890123456789.12";
        model.applyFilters()
        #expect(model.filterVisible && model.filterError != nil);
        #expect(await loader.queries.count == 1)
        model.stop()
    }
    @Test func featuredEntryAppendSortFiltersKeywordAndResetStayInFeaturedScope() async {
        let loader = SearchPageGate(); let history = SearchHistoryFake()
        let model = SearchResultsViewModel(
            keyword: "", loader: loader,
            categories: SearchCategoryFake(), history: history, featuredOnly: true)
        #expect(model.query.isValid && model.query.keyword.isEmpty)
        let initial = Task { await model.activate(true) }; await loader.wait(1)
        await loader.succeed(0, total: 11); await initial.value
        #expect(await history.recorded.isEmpty)
        model.more(); await loader.wait(2); await loader.succeed(1, id: 11, total: 11)
        for _ in 0..<1000 { if model.state.items.count == 11 { break }; await Task.yield() }
        #expect(model.state.items.count == 11)
        model.sort("sales"); await loader.wait(3); await loader.succeed(2)
        model.showFilters(); model.minimumDraft = "100"; model.selectedCategories = [2]
        model.applyFilters(); await loader.wait(4); await loader.succeed(3)
        model.draft = " 手机 "; await model.submitKeyword(); await loader.wait(5)
        await loader.succeed(4)
        #expect(await history.recorded == ["手机"])
        model.draft = ""; await model.submitKeyword(); await loader.wait(6)
        await loader.succeed(5)
        model.showFilters(); model.resetFilters(); model.applyFilters(); await loader.wait(7)
        await loader.succeed(6)
        let queries = await loader.queries
        #expect(queries.allSatisfy { $0.0.featuredOnly && $0.0.isValid })
        #expect(queries.map { $0.1 } == [1, 2, 1, 1, 1, 1, 1])
        #expect(queries.last?.0.keyword == "" && queries.last?.0.categoryIDs == [])
        #expect(queries.last?.0.sort == .salesAscending)
        #expect(await history.recorded == ["手机"])
        model.stop()
    }
    @Test func featuredCurrentFailureRetryRejectsLateFailureAndRetainsCollectionOnReturn()
        async throws
    {
        let loader = SearchPageGate()
        let model = SearchResultsViewModel(
            keyword: "", loader: loader,
            categories: SearchCategoryFake(), history: SearchHistoryFake(), featuredOnly: true)
        let initial = Task { await model.activate(true) }; await loader.wait(1)
        model.sort("price"); await loader.wait(2)
        await loader.fail(1)
        for _ in 0..<1000 { if model.state.failure != nil { break }; await Task.yield() }
        #expect(model.state.failure == .timeout)
        model.retry(); await loader.wait(3); await loader.succeed(2, id: 8)
        await settle(model, id: 8)
        try #require(model.state.items.map(\.id) == [8])
        await loader.fail(0); await initial.value
        #expect(model.state.items.map(\.id) == [8] && model.state.failure == nil)
        model.stop(); await model.activate(true)
        #expect(await loader.queries.count == 3)
        #expect(await loader.queries.allSatisfy { $0.0.featuredOnly })
        model.stop()
    }
    private func settle(_ model: SearchResultsViewModel, id: Int64) async {
        for _ in 0..<100 { if model.state.items.first?.id == id { break }; await Task.yield() }
    }
}
private struct SearchCategoryFake: CategoryLoading {
    func loadCategories() -> [CategoryNode] { [] }
}
private actor SearchPageGate: ProductSearchLoading {
    var queries: [(SearchQuery, Int, Int)] = []
    private var gates: [Int: CheckedContinuation<NumberedPage<SearchProductSummary>, any Error>] =
        [:]
    private var waits: [(Int, CheckedContinuation<Void, Never>)] = []
    func search(_ query: SearchQuery, page: Int, pageSize: Int) async throws -> NumberedPage<
        SearchProductSummary
    > {
        let index = queries.count; queries.append((query, page, pageSize))
        return try await withCheckedThrowingContinuation { gate in
            gates[index] = gate
            let ready = waits.filter { queries.count >= $0.0 };
            waits.removeAll { queries.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func wait(_ count: Int) async {
        if queries.count >= count { return }
        await withCheckedContinuation { waits.append((count, $0)) }
    }
    func succeed(_ index: Int, id: Int64 = 1, total: Int64 = 1) {
        let request = queries[index];
        let count = Int(min(Int64(request.2), total - Int64((request.1 - 1) * request.2)))
        let items = (0..<count).map { offset in
            SearchProductSummary(
                id: id + Int64(offset), title: "商品", subtitle: nil, imageURL: nil, priceYuan: 100,
                sold: 2)
        }
        gates.removeValue(forKey: index)?.resume(
            returning: .init(items: items, page: request.1, size: request.2, total: total))
    }
    func fail(_ index: Int) {
        gates.removeValue(forKey: index)?.resume(throwing: PageReadFailure.timeout)
    }
}

private struct AccountSearchHistory: SearchHistoryRecording {
    let scope = SearchHistoryScope(environment: "test", accountID: "a")
    func record(_ keyword: String) {}
}
