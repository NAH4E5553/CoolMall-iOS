import Foundation
import MallCore
import Testing

struct BuyNowIntentTests {
    private let product = ProductDetailSnapshot(
        id: 9, title: "商品", subtitle: nil, priceYuan: 999,
        sold: 0, isAvailable: true, imageURLs: [], contentImageURLs: [])
    private func spec(price: Decimal = 999, stock: Int64 = 3, product: Int64 = 9)
        -> ProductSpecification
    {
        ProductSpecification(
            id: 4, productID: product, name: "规格", priceYuan: price, stock: stock, imageURLs: [])
    }
    @Test func validatedSelectionUsesExactSkuSubtotalWithoutCouponOrFreight() throws {
        let intent = try BuyNowIntent(
            product: product, specification: spec(price: Decimal(string: "999.15")!), quantity: 2)
        #expect(intent.subtotalYuan == Decimal(string: "1998.30")); #expect(intent.quantity == 2)
        #expect(intent.specificationID == 4); #expect(intent.productID == 9)
    }
    @Test func invalidQuantityStockIdentityAndMoneyFailBeforeNavigation() {
        for quantity: Int64 in [0, -1, 4] {
            #expect(throws: ShoppingCartFailure.self) {
                try BuyNowIntent(product: product, specification: spec(), quantity: quantity)
            }
        }
        #expect(throws: ShoppingCartFailure.self) {
            try BuyNowIntent(product: product, specification: spec(product: 8), quantity: 1)
        }
        #expect(throws: ShoppingCartFailure.self) {
            try BuyNowIntent(product: product, specification: spec(price: -1), quantity: 1)
        }
        #expect(throws: ShoppingCartFailure.self) {
            try BuyNowIntent(
                product: product, specification: spec(price: Decimal(Int64.max)), quantity: 2)
        }
    }
    @Test func statusFiltersDoNotUseVisibleTabIndices() {
        #expect(OrderFilter.all.wireStatuses == nil);
        #expect(OrderFilter.afterSale.wireStatuses == [5, 6])
        #expect(OrderFilter.unevaluated.wireStatuses == [3]);
        #expect(OrderFilter.completed.wireStatuses == [4])
    }
}
