import Foundation
import MallCore
import Observation

/// One Me-section/account identity owns this transient server projection; no persisted counter.
@MainActor @Observable final class OrderCountsViewModel {
    private let accountID: Int64?
    private let loader: (any OrderCountsLoading)?
    private var generation: UInt64 = 0
    private var active = false
    private(set) var counts: UserOrderCounts?
    private(set) var failure: PageReadFailure?
    private(set) var loading = false
    init(accountID: Int64?, loader: (any OrderCountsLoading)?) {
        self.accountID = accountID; self.loader = loader
    }
    func activate(_ active: Bool) async {
        guard !Task.isCancelled else { return }
        generation &+= 1; let epoch = generation; self.active = active
        loading = false
        guard active, let accountID, accountID > 0, let loader else {
            counts = nil; failure = nil; return
        }
        counts = nil; failure = nil; loading = true
        defer { if generation == epoch { loading = false } }
        do {
            let value = try await loader.loadOrderCounts(accountID: accountID)
            try Task.checkCancellation()
            guard self.active, generation == epoch else { return }; counts = value
        } catch {
            guard self.active, generation == epoch, !Task.isCancelled,
                !(error is CancellationError)
            else { return }
            failure = (error as? PageReadFailure) ?? .invalidResponse
        }
    }
    func stop() { active = false; generation &+= 1; loading = false; counts = nil }
}
