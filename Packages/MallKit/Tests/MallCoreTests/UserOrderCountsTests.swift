import MallCore
import Testing

struct UserOrderCountsTests {
    @Test func serverCountsPreserveZeroMissingAndAfterSaleSum() throws {
        let value = try UserOrderCounts(
            unpaid: 100, unshipped: 0, unreceived: 3,
            unevaluated: 4, refunding: 5, refunded: 6)
        #expect(value.count(for: .unpaid) == 100)
        #expect(value.count(for: .unshipped) == 0)
        #expect(value.count(for: .unreceived) == 3)
        #expect(value.count(for: .unevaluated) == 4)
        #expect(value.count(for: .afterSale) == 11)
        #expect(value.count(for: .all) == nil)
        #expect(try UserOrderCounts(refunding: 5).afterSale == nil)
        #expect(try UserOrderCounts(refunded: 6).afterSale == nil)
        #expect(try UserOrderCounts().unpaid == nil)
    }
    @Test func invalidCountsAndOverflowAreRejected() {
        #expect(throws: PageReadFailure.invalidResponse) { try UserOrderCounts(unpaid: -1) }
        #expect(throws: PageReadFailure.invalidResponse) { try UserOrderCounts(refunding: -1) }
        #expect(throws: PageReadFailure.invalidResponse) {
            try UserOrderCounts(refunding: Int64.max, refunded: 1)
        }
    }
}
