import MallCore
import Testing
@testable import CatalogFeature

@MainActor struct HomeGoodsViewModelTests {
    @Test func cancelledAutomaticInitialReadRestartsOnReturnButFailureNeverRetriesAutomatically()
        async
    {
        let loader = HomeGoodsGate(); let model = HomeGoodsViewModel(loader: loader)
        model.setActive(true); model.tailVisibilityChanged(true); await loader.wait(1)
        model.setActive(false)
        await loader.complete(0, start: 1, count: 10, total: 10)
        #expect(await loader.waitForReturn(0))
        model.setActive(true); model.tailVisibilityChanged(true); await loader.wait(2)
        await loader.fail(1); await settled(model)
        #expect(model.state.failure == .timeout)
        model.setActive(false); model.setActive(true)
        model.tailVisibilityChanged(true)
        #expect(await loader.reads.count == 2)
        model.loadMore(); await loader.wait(3)
        await loader.complete(2, start: 1, count: 1, total: 1); await settled(model)
        #expect(model.state.items.map(\.id) == [1])
        model.setActive(false)
    }

    @Test func resetRejectsLateAppendAndNoProgressRequiresExplicitRecovery() async {
        let loader = HomeGoodsGate(); let model = HomeGoodsViewModel(loader: loader)
        model.setActive(true); model.loadMore(); await loader.wait(1)
        await loader.complete(0, start: 1, count: 10, total: 20); await settled(model)
        model.loadMore(); await loader.wait(2)
        // A successful home refresh replaces the catalogue owner while page 2 is in flight.
        model.reset(); model.loadMore(); await loader.wait(3)
        await loader.complete(2, start: 101, count: 10, total: 20); await settled(model)
        await loader.complete(1, start: 11, count: 10, total: 20)
        #expect(await loader.waitForReturn(1))
        #expect(model.state.items.map(\.id) == (101...110).map { Int64($0) })
        model.loadMore(); await loader.wait(4)
        await loader.complete(3, start: 101, count: 10, total: 20); await settled(model)
        #expect(model.state.appendFailure == .noProgress && model.state.nextPage == 2)
        model.tailVisibilityChanged(true)
        #expect(await loader.reads.count == 4)
        model.setActive(false)
    }

    @Test func startsAtPageOneDeduplicatesTailRetriesSamePageAndStopsAtTotal() async {
        let loader = HomeGoodsGate(); let model = HomeGoodsViewModel(loader: loader)
        model.setActive(true)
        model.tailVisibilityChanged(true); model.loadMore(); await loader.wait(1)
        #expect(await loader.reads.count == 1)
        await loader.complete(0, start: 1, count: 10, total: 21)
        await loader.wait(2)
        #expect(model.state.items.count == 10 && model.state.nextPage == 2)
        // Calibration consumes the same tail intent with exactly one page-2 read.
        model.tailVisibilityChanged(true); #expect(await loader.reads.count == 2)
        await loader.fail(1); await settled(model)
        #expect(model.state.items.count == 10 && model.state.appendFailure == .timeout)
        model.tailVisibilityChanged(false); model.tailVisibilityChanged(true)
        #expect(await loader.reads.count == 2)
        model.loadMore(); await loader.wait(3)
        await loader.complete(2, start: 11, count: 10, total: 21); await settled(model)
        model.loadMore(); await loader.wait(4)
        await loader.complete(3, start: 21, count: 1, total: 21); await settled(model)
        model.loadMore(); #expect(await loader.reads.count == 4)
        #expect(model.state.items.map(\.id) == (1...21).map { Int64($0) })
        let reads = await loader.reads
        #expect(reads.map { $0.1 } == [1, 2, 2, 3])
        #expect(
            reads.allSatisfy {
                $0.0.allProducts && $0.0.keyword.isEmpty && $0.0.categoryIDs.isEmpty && $0.2 == 10
            })
        model.setActive(false)
    }

    @Test func failedInitialReadKeepsPreviewAndLeavingRejectsLateSuccess() async {
        let loader = HomeGoodsGate(); let model = HomeGoodsViewModel(loader: loader)
        let preview = [
            HomeProductSummary(id: 99, title: "首页预览", subtitle: nil, imageURL: nil, priceYuan: 1)
        ]
        model.setActive(true); model.loadMore(); await loader.wait(1)
        await loader.fail(0); await settled(model)
        #expect(model.products(fallback: preview) == preview)
        model.loadMore(); await loader.wait(2); model.setActive(false)
        await loader.complete(1, start: 1, count: 1, total: 1)
        #expect(await loader.waitForReturn(1))
        #expect(model.products(fallback: preview) == preview)
        model.setActive(true); model.loadMore(); await loader.wait(3)
        await loader.complete(2, start: 1, count: 1, total: 1); await settled(model)
        #expect(model.products(fallback: preview).map(\.id) == [1])
        model.setActive(false)
    }

    @Test func acceptedRefreshCancelsAppendFailedRefreshRetainsPagesAndSuccessResets() async {
        let snapshot = HomeSnapshot(
            banners: [], categories: [], allCategories: [], featured: [], recommendations: [],
            goods: [], coupons: [])
        let home = HomeViewModelTests.ScriptedService(steps: [
            .value(snapshot), .failure(.networkUnavailable), .value(snapshot),
        ])
        let loader = HomeGoodsGate(); let page = HomeViewModel(home: home, goods: loader)
        await page.drive(active: true, retryToken: 0)
        guard let model = page.goods else { Issue.record("missing home goods owner"); return }
        model.loadMore(); await loader.wait(1)
        await loader.complete(0, start: 1, count: 10, total: 11); await settled(model)
        model.loadMore(); await loader.wait(2)
        await page.pullToRefresh()
        #expect(page.refreshFailedHint && model.state.items.count == 10)
        await loader.complete(1, start: 11, count: 1, total: 11)
        #expect(await loader.waitForReturn(1))
        #expect(model.state.items.count == 10)
        await page.pullToRefresh()
        #expect(!model.state.hasLoaded && model.state.items.isEmpty)
        model.loadMore(); await loader.wait(3)
        let reads = await loader.reads
        #expect(reads.map { $0.1 } == [1, 2, 1])
        await loader.complete(2, start: 1, count: 1, total: 1); await settled(model)
        page.pageTeardown()
    }

    private func settled(_ model: HomeGoodsViewModel) async {
        for _ in 0..<1000 { if model.state.operation == nil { return }; await Task.yield() }
        Issue.record("page operation did not settle")
    }
}

private actor HomeGoodsGate: ProductSearchLoading {
    var reads: [(SearchQuery, Int, Int)] = []
    private var pending: [Int: CheckedContinuation<NumberedPage<SearchProductSummary>, any Error>] =
        [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var returned: [Int: Bool] = [:]
    private var returnWaiters: [Int: [CheckedContinuation<Bool, Never>]] = [:]
    /// Acknowledges the actual read task returning with cancellation, rather than just resuming
    /// its continuation. The unchanged coordinator checks cancellation before any commit.
    func waitForReturn(_ index: Int) async -> Bool {
        if let cancelled = returned[index] { return cancelled }
        return await withCheckedContinuation { returnWaiters[index, default: []].append($0) }
    }
    // Deliberately ignores cancellation so the real owner's stale-result guard is exercised.
    func search(_ query: SearchQuery, page: Int, pageSize: Int) async throws -> NumberedPage<
        SearchProductSummary
    > {
        let index = reads.count; reads.append((query, page, pageSize))
        defer {
            let cancelled = Task.isCancelled
            returned[index] = cancelled
            for waiter in returnWaiters.removeValue(forKey: index) ?? [] {
                waiter.resume(returning: cancelled)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            let ready = waiters.filter { $0.0 <= reads.count }
            waiters.removeAll { $0.0 <= reads.count }
            for (_, waiter) in ready { waiter.resume() }
        }
    }
    func wait(_ count: Int) async {
        if reads.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func fail(_ index: Int) {
        pending.removeValue(forKey: index)?.resume(throwing: PageReadFailure.timeout)
    }
    func complete(_ index: Int, start: Int, count: Int, total: Int64) {
        let products = (start..<(start + count)).map {
            SearchProductSummary(
                id: Int64($0), title: "商品\($0)", subtitle: nil, imageURL: nil, priceYuan: 1,
                sold: nil)
        }
        pending.removeValue(forKey: index)?.resume(
            returning: NumberedPage(
                items: products, page: reads[index].1, size: reads[index].2, total: total))
    }
}
