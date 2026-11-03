import Foundation

/// Server counts, not totals reconstructed from a partially loaded order list.
public struct UserOrderCounts: Equatable, Sendable {
    public let unpaid: Int64?
    public let unshipped: Int64?
    public let unreceived: Int64?
    public let unevaluated: Int64?
    public let afterSale: Int64?
    public init(
        unpaid: Int64? = nil, unshipped: Int64? = nil, unreceived: Int64? = nil,
        unevaluated: Int64? = nil, refunding: Int64? = nil, refunded: Int64? = nil
    ) throws {
        guard
            [unpaid, unshipped, unreceived, unevaluated, refunding, refunded]
                .allSatisfy({ $0.map { $0 >= 0 } ?? true })
        else { throw PageReadFailure.invalidResponse }
        self.unpaid = unpaid; self.unshipped = unshipped; self.unreceived = unreceived
        self.unevaluated = unevaluated
        if let refunding, let refunded {
            let (sum, overflow) = refunding.addingReportingOverflow(refunded)
            guard !overflow else { throw PageReadFailure.invalidResponse }; afterSale = sum
        } else {
            afterSale = nil
        }
    }
    public func count(for filter: OrderFilter) -> Int64? {
        switch filter {
        case .unpaid: unpaid
        case .unshipped: unshipped
        case .unreceived: unreceived
        case .unevaluated: unevaluated
        case .afterSale: afterSale
        case .all, .completed: nil
        }
    }
}
public protocol OrderCountsLoading: Sendable {
    func loadOrderCounts(accountID: Int64) async throws -> UserOrderCounts
}
