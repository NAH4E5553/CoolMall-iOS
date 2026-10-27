import Foundation
import MallCore
import Observation

@MainActor @Observable final class OrderListViewModel {
    private let accountID: Int64
    private let loader: any OrdersLoading
    private var coordinators: [OrderFilter: NumberedPageCoordinator<OrderSnapshot>] = [:]
    private var snapshots: [OrderFilter: NumberedPageSnapshot<OrderSnapshot>] = [:]
    private(set) var filter: OrderFilter
    var state: NumberedPageSnapshot<OrderSnapshot> { snapshot(for: filter) }
    init(accountID: Int64, filter: OrderFilter, loader: any OrdersLoading) {
        self.accountID = accountID; self.filter = filter; self.loader = loader
        rebuildPages()
    }
    private func rebuildPages() {
        for page in coordinators.values { page.setActive(false); page.onChange = nil }
        coordinators = [:]; snapshots = [:]
        for filter in OrderFilter.allCases {
            let accountID = accountID; let loader = loader
            let page = NumberedPageCoordinator<OrderSnapshot>(pageSize: 10) { number, size in
                try await loader.loadOrders(
                    accountID: accountID, filter: filter, page: number, pageSize: size)
            }
            coordinators[filter] = page; snapshots[filter] = page.snapshot
            page.onChange = { [weak self] in self?.snapshots[filter] = $0 }
        }
    }
    func snapshot(for filter: OrderFilter) -> NumberedPageSnapshot<OrderSnapshot> {
        // All seven fixed filters are installed together, never inferred from loaded orders.
        snapshots[filter]!
    }
    func select(_ filter: OrderFilter) {
        guard filter != self.filter else { return }
        coordinators[self.filter]?.setActive(false); self.filter = filter
    }
    /// Writes and reauthentication invalidate every filter, including offscreen cached pages.
    func invalidateAll() { rebuildPages() }
    func prepareLogin() { invalidateAll() }
    func activate(_ active: Bool) async {
        guard !Task.isCancelled else { return }
        let page = coordinators[filter]!
        page.setActive(active)
        if active { await page.loadInitial() }
    }
    func stop() { for page in coordinators.values { page.setActive(false) } }
    func refresh(for expected: OrderFilter? = nil) async {
        guard expected == nil || expected == filter else { return }
        await coordinators[filter]?.refresh()
    }
    func retry() { coordinators[filter]?.retry() }
    func more(automatic: Bool = false, for expected: OrderFilter? = nil) {
        guard expected == nil || expected == filter else { return }
        coordinators[filter]?.loadMore(automatic: automatic)
    }
    func tailExited(for expected: OrderFilter? = nil) {
        guard expected == nil || expected == filter else { return }
        coordinators[filter]?.tailExited()
    }
}

@MainActor @Observable final class OrderDetailViewModel {
    private let accountID: Int64
    private let orderID: Int64
    private let loader: any OrdersLoading
    private let canceller: (any OrderCancelling)?
    private var lifecycle: UInt64 = 0
    private var writing = false
    private(set) var cancelLocked = false
    private(set) var reasons: [OrderCancelReason]?
    private(set) var reasonsLoading = false
    private(set) var selectedReason: OrderCancelReason?
    private(set) var cancelFailure: OrderWriteFailure?
    private(set) var cancelling = false
    private var generation: UInt64 = 0
    private var active = false
    private var needsRead = true
    private(set) var order: OrderSnapshot?
    private(set) var failure: PageReadFailure?
    private(set) var loading = false
    private(set) var attempt = 0
    init(
        accountID: Int64, orderID: Int64, loader: any OrdersLoading,
        canceller: (any OrderCancelling)? = nil
    ) {
        self.accountID = accountID; self.orderID = orderID; self.loader = loader;
        self.canceller = canceller
    }
    func retry() { needsRead = true; failure = nil; attempt += 1 }
    func activate(_ active: Bool) async {
        let returning = !self.active && active
        self.active = active
        if returning, order != nil { needsRead = true }
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
    var canCancel: Bool {
        active && order?.status == 0 && !cancelLocked && !writing && canceller != nil
    }
    func clearCancelFailure() { cancelFailure = nil }
    func selectReason(_ reason: OrderCancelReason) {
        guard !writing, reasons?.contains(reason) == true else { return }; selectedReason = reason
    }
    func loadReasons() async {
        guard canCancel, !reasonsLoading, let canceller else { return }
        let epoch = lifecycle; reasonsLoading = true; cancelFailure = nil
        defer { if epoch == lifecycle { reasonsLoading = false } }
        do {
            let values = try await canceller.loadCancelReasons(accountID: accountID)
            try Task.checkCancellation()
            guard active, epoch == lifecycle else { return }
            reasons = values; selectedReason = values.first
        } catch {
            guard active, epoch == lifecycle else { return }
            cancelFailure =
                (error as? OrderWriteFailure)
                ?? ((error as? PageReadFailure) == .authenticationRequired
                    ? .authenticationRequired : .unavailable)
        }
    }
    /// Acknowledgement alone never fabricates a closed order; refresh owns the status.
    func cancel() async -> Bool {
        guard canCancel, let reason = selectedReason, let canceller else { return false }
        let epoch = lifecycle; writing = true; cancelling = true; cancelFailure = nil
        defer { writing = false; cancelling = false }
        do {
            try await canceller.cancelOrder(accountID: accountID, orderID: orderID, reason: reason)
            guard active, epoch == lifecycle, !Task.isCancelled else { return false }
            cancelLocked = true
            // A read started before acknowledgement cannot replace the required post-write read.
            generation &+= 1; loading = false
            await refresh()
            return true
        } catch {
            guard active, epoch == lifecycle else { return false }
            let failure = (error as? OrderWriteFailure) ?? .unconfirmed
            if failure == .unconfirmed { cancelLocked = true }
            cancelFailure = failure; return false
        }
    }
    func stop() {
        active = false; lifecycle &+= 1; generation &+= 1; loading = false; reasonsLoading = false;
        cancelling = false
    }
}
