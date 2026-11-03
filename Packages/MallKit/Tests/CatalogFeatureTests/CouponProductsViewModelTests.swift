import Foundation
import MallCore
import Testing
@testable import CatalogFeature

@MainActor struct CouponProductsViewModelTests {
    @Test func exactMinimumBoundAcrossRefreshAndFailureRecovery() async {
        let loader = CouponProductsModelLoader()
        let amount = Decimal(string: "299.15")
        let model = CouponProductsViewModel(minimum: amount, loader: loader)
        await model.activate(true); #expect(model.state.items.map(\.id) == [7])
        await model.refresh(); #expect(model.state.failure == .timeout);
        #expect(model.state.items.map(\.id) == [7])
        await model.refresh(); #expect(model.state.failure == nil)
        #expect(await loader.queries == [amount, amount, amount])
        model.stop(); await model.refresh(); #expect(await loader.queries.count == 3)
    }
    @Test func missingMinimumStaysUnfilteredAndInitialReadIsNotRepeatedOnReturn() async {
        let loader = CouponProductsModelLoader()
        let model = CouponProductsViewModel(minimum: nil, loader: loader)
        await model.activate(true); model.stop(); await model.activate(true)
        #expect(await loader.queries.count == 1); #expect(await loader.queries.first == .some(nil))
        #expect(model.state.items.map(\.id) == [7])
    }
}
private actor CouponProductsModelLoader: CouponProductsLoading {
    var queries: [Decimal?] = []
    func loadProducts(minimumPriceYuan: Decimal?, page: Int, pageSize: Int) throws -> NumberedPage<
        CouponProductSummary
    > {
        queries.append(minimumPriceYuan)
        if queries.count == 2 { throw PageReadFailure.timeout }
        return NumberedPage(
            items: [
                CouponProductSummary(
                    id: 7, title: "商品", subtitle: nil, imageURL: nil, priceYuan: 4999, sold: 1)
            ], page: page, size: pageSize, total: 1)
    }
}
