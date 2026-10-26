import Foundation
import MallCore
import Testing
@testable import AccountFeature

@MainActor struct CouponViewModelTests {
    @Test func accountBoundReadRefreshFailureRetainsSnapshotAndRetry() async {
        let loader = CouponModelLoader()
        let model = CouponViewModel(accountID: 17, loader: loader)
        await model.activate(true)
        #expect(model.state.items.map(\.id) == [17]); #expect(model.state.total == 1)
        #expect(await loader.accounts == [17])
        await model.refresh()
        #expect(model.state.failure == .authenticationRequired);
        #expect(model.state.items.map(\.id) == [17])
        model.retry()
        for _ in 0..<10000 { if model.state.operation == nil { break }; await Task.yield() }
        #expect(model.state.failure == nil); #expect(model.state.items.map(\.id) == [17])
        model.stop(); await model.refresh(); #expect(await loader.accounts.count == 3)
    }
    @Test func newAccountHasNewStateAndGuestIsNeverAQuery() async {
        let loader = CouponModelLoader()
        let first = CouponViewModel(accountID: 17, loader: loader)
        await first.activate(true); first.stop()
        let second = CouponViewModel(accountID: 28, loader: loader)
        #expect(second.state.items.isEmpty); #expect(!second.state.hasLoaded)
        await second.activate(true)
        #expect(second.state.failure == .authenticationRequired)
        await second.refresh(); #expect(second.state.items.map(\.id) == [28])
        #expect(await loader.accounts == [17, 28, 28])
    }
}
private actor CouponModelLoader: UserCouponsLoading {
    var accounts: [Int64] = []
    func loadCoupons(accountID: Int64, page: Int, pageSize: Int) throws -> NumberedPage<UserCoupon>
    {
        accounts.append(accountID)
        if accounts.count == 2 { throw PageReadFailure.authenticationRequired }
        return NumberedPage(
            items: [
                UserCoupon(
                    id: accountID, title: "券", description: "", amountYuan: 1,
                    minimumSpendYuan: nil, startTime: "2020-01-01T00:00:00",
                    endTime: "2030-01-01T00:00:00", type: 0, status: 1, useStatus: 0)
            ], page: page, size: pageSize, total: 1)
    }
}
