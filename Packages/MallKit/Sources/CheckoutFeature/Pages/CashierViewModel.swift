import Foundation
import MallCore
import Observation

@MainActor @Observable final class CashierViewModel {
    private let accountID: Int64
    private let orderID: Int64
    private let loader: any OrdersLoading
    private var generation: UInt64 = 0
    private(set) var order: OrderSnapshot?
    private(set) var loading = false
    private(set) var failure: PageReadFailure?
    private(set) var attempt = 0
    init(accountID: Int64, orderID: Int64, loader: any OrdersLoading) {
        self.accountID = accountID; self.orderID = orderID; self.loader = loader
    }
    func retry() { attempt += 1 }
    func activate(_ active: Bool) async {
        generation &+= 1; let epoch = generation
        loading = false
        guard active else { return }
        loading = true; failure = nil
        defer { if generation == epoch { loading = false } }
        do {
            let value = try await loader.loadOrder(accountID: accountID, orderID: orderID)
            try Task.checkCancellation()
            guard epoch == generation else { return }
            guard value.id == orderID else { throw PageReadFailure.invalidResponse }
            order = value
        } catch {
            guard epoch == generation, !Task.isCancelled else { return }
            failure = (error as? PageReadFailure) ?? .invalidResponse
        }
    }
    func stop() { generation &+= 1; loading = false }
}
