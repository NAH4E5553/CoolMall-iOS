import Foundation
import MallCore
import Observation

@MainActor @Observable final class OrderListViewModel {
    private let accountID: Int64
    private let loader: any OrdersLoading
    private var pages: NumberedPageCoordinator<OrderSnapshot>
    private(set) var filter: OrderFilter
    private(set) var state: NumberedPageSnapshot<OrderSnapshot>
    init(accountID: Int64, filter: OrderFilter, loader: any OrdersLoading) {
        self.accountID = accountID; self.filter = filter; self.loader = loader
        let pages = Self.makePages(accountID: accountID, filter: filter, loader: loader)
        self.pages = pages; state = pages.snapshot
        pages.onChange = { [weak self] in self?.state = $0 }
    }
    private static func makePages(accountID: Int64, filter: OrderFilter, loader: any OrdersLoading)
        -> NumberedPageCoordinator<OrderSnapshot>
    {
        NumberedPageCoordinator(pageSize: 10) { page, size in
            try await loader.loadOrders(
                accountID: accountID, filter: filter, page: page, pageSize: size)
        }
    }
    func select(_ filter: OrderFilter) {
        guard filter != self.filter else { return }
        pages.setActive(false); pages.onChange = nil
        self.filter = filter
        pages = Self.makePages(accountID: accountID, filter: filter, loader: loader)
        state = pages.snapshot; pages.onChange = { [weak self] in self?.state = $0 }
    }
    func prepareLogin() {
        pages.setActive(false); pages.onChange = nil
        pages = Self.makePages(accountID: accountID, filter: filter, loader: loader)
        state = pages.snapshot; pages.onChange = { [weak self] in self?.state = $0 }
    }
    func activate(_ active: Bool) async {
        pages.setActive(active)
        if active { await pages.loadInitial() }
    }
    func stop() { pages.setActive(false) }
    func refresh() async { await pages.refresh() }
    func retry() { pages.retry() }
    func more(automatic: Bool = false) { pages.loadMore(automatic: automatic) }
    func tailExited() { pages.tailExited() }
}

@MainActor @Observable final class OrderDetailViewModel {
    private let accountID: Int64
    private let orderID: Int64
    private let loader: any OrdersLoading
    private var generation: UInt64 = 0
    private var active = false
    private var needsRead = true
    private(set) var order: OrderSnapshot?
    private(set) var failure: PageReadFailure?
    private(set) var loading = false
    private(set) var attempt = 0
    init(accountID: Int64, orderID: Int64, loader: any OrdersLoading) {
        self.accountID = accountID; self.orderID = orderID; self.loader = loader
    }
    func retry() { needsRead = true; failure = nil; attempt += 1 }
    func activate(_ active: Bool) async {
        self.active = active
        guard active else { stop(); return }
        guard needsRead, failure == nil, !loading else { return }
        await refresh()
    }
    func refresh() async {
        guard active, !loading, !Task.isCancelled else { return }
        generation &+= 1; let epoch = generation; loading = true; failure = nil
        defer { if generation == epoch { loading = false } }
        do {
            let value = try await loader.loadOrder(accountID: accountID, orderID: orderID)
            try Task.checkCancellation()
            guard active, epoch == generation else { return }
            guard value.id == orderID else { throw PageReadFailure.invalidResponse }
            order = value; needsRead = false
        } catch {
            guard active, epoch == generation, !Task.isCancelled, !(error is CancellationError)
            else { return }
            needsRead = true; failure = (error as? PageReadFailure) ?? .invalidResponse
        }
    }
    func stop() { active = false; generation &+= 1; loading = false }
}
