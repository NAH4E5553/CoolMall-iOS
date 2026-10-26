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
    @Test func cartIntentUsesSelectedFreshSpecificationsAndExactAggregateWithoutWritingCart() throws
    {
        let specifications = [
            spec(price: 120),
            ProductSpecification(
                id: 5, productID: 9,
                name: "second", priceYuan: 200, stock: 3, imageURLs: []),
        ]
        let quotes = specifications.map {
            CartQuote(
                productID: 9, specificationID: $0.id,
                title: "商品", specification: $0.name, imageURL: nil,
                price: try! CartMoney(yuan: 100), stock: 3)
        }
        let cart = ShoppingCartSnapshot(
            scope: .init(environment: "test", accountID: nil),
            revision: 4, lines: quotes.map { CartLine(quote: $0, quantity: 2) })
        let check = CartProductCheck(
            productID: 9, isAvailable: true, quotes: quotes,
            product: product, specifications: specifications)
        let all = try CheckoutIntent(
            cart: cart, selection: Set(quotes.map(\.id)), checks: [9: check])
        #expect(all.lines.map(\.specificationID) == [4, 5]); #expect(all.subtotalYuan == 640)
        #expect(all.pricesChanged); #expect(cart.lines[0].unitPrice.yuan == 100)
        let one = try CheckoutIntent(cart: cart, selection: [quotes[1].id], checks: [9: check])
        #expect(one.lines.count == 1); #expect(one.subtotalYuan == 400)
        #expect(one.source == .cart(scope: cart.scope, revision: 4))
        #expect(throws: ShoppingCartFailure.missingLine) {
            try CheckoutIntent(cart: cart, selection: [], checks: [9: check])
        }
        #expect(throws: ShoppingCartFailure.unavailable) {
            try CheckoutIntent(cart: cart, selection: [quotes[0].id], checks: [:])
        }
        let richMissing = CartProductCheck(productID: 9, isAvailable: true, quotes: quotes)
        #expect(throws: ShoppingCartFailure.unavailable) {
            try CheckoutIntent(cart: cart, selection: [quotes[0].id], checks: [9: richMissing])
        }
    }

    @Test func multipleProductsAggregateExactCentsAndRejectCombinedOverflow() throws {
        for price: Decimal in [Decimal(string: "0.15")!, Decimal(string: "50000000000000000")!] {
            var checks: [Int64: CartProductCheck] = [:]
            var lines: [CartLine] = []
            for id: Int64 in [9, 10] {
                let product = ProductDetailSnapshot(
                    id: id, title: "product-\(id)", subtitle: nil,
                    priceYuan: price, sold: 0, isAvailable: true, imageURLs: [],
                    contentImageURLs: [])
                let sku = ProductSpecification(
                    id: 4, productID: id, name: "sku", priceYuan: price,
                    stock: 1, imageURLs: [])
                let quote = CartQuote(
                    productID: id, specificationID: 4, title: product.title,
                    specification: sku.name, imageURL: nil, price: try CartMoney(yuan: price),
                    stock: 1)
                lines.append(CartLine(quote: quote, quantity: 1))
                checks[id] = .init(
                    productID: id, isAvailable: true, quotes: [quote], product: product,
                    specifications: [sku])
            }
            let cart = ShoppingCartSnapshot(
                scope: .init(environment: "test", accountID: "1"), revision: 7, lines: lines)
            if price < 1 {
                let intent = try CheckoutIntent(
                    cart: cart, selection: Set(lines.map(\.id)), checks: checks)
                #expect(intent.lines.map(\.productID) == [9, 10])
                #expect(intent.subtotalYuan == Decimal(string: "0.30"))
            } else {
                #expect(throws: ShoppingCartFailure.self) {
                    try CheckoutIntent(cart: cart, selection: Set(lines.map(\.id)), checks: checks)
                }
            }
        }
    }

}
