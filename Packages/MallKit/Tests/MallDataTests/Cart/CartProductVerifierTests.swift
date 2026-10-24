import Foundation
import MallCore
import MallData
import Testing

private struct CheckedProductSource: ProductDetailLoading {
    let available: Bool
    let specs: [ProductSpecification]
    func loadDetail(productID: Int64) async throws -> ProductDetailSnapshot {
        .init(
            id: productID, title: "商品", subtitle: nil, priceYuan: 3999,
            sold: 0, isAvailable: available, imageURLs: [], contentImageURLs: [])
    }
    func loadSpecifications(productID: Int64) async throws -> [ProductSpecification] { specs }
}
@Suite struct CartProductVerifierTests {
    @Test func mapsYuanAndInt64StockWithoutInventingSpecOrCartEndpoint() async throws {
        let spec = ProductSpecification(
            id: 2, productID: 1, name: "白 256GB", priceYuan: 3999,
            stock: 297, imageURLs: [])
        let check = try await CartProductVerifier(
            loader: CheckedProductSource(available: true, specs: [spec])
        ).check(productID: 1)
        let quote = try check.quote(for: .init(productID: 1, specificationID: 2))
        #expect(quote.price.cents == 399900); #expect(quote.stock == 297);
        #expect(quote.specification == spec.name)
        #expect(throws: ShoppingCartFailure.unavailable) {
            try check.quote(for: .init(productID: 1, specificationID: 3))
        }
    }
    @Test func unavailableProductAndZeroStockCannotBecomePurchasable() async throws {
        let check = try await CartProductVerifier(
            loader: CheckedProductSource(available: false, specs: [])
        ).check(productID: 1)
        #expect(throws: ShoppingCartFailure.unavailable) {
            try check.quote(for: .init(productID: 1, specificationID: 2))
        }
        let spec = ProductSpecification(
            id: 2, productID: 1, name: "白", priceYuan: 1, stock: 0, imageURLs: [])
        let empty = try await CartProductVerifier(
            loader: CheckedProductSource(available: true, specs: [spec])
        ).check(productID: 1)
        #expect(throws: ShoppingCartFailure.insufficientStock(available: 0)) {
            try empty.quote(for: .init(productID: 1, specificationID: 2))
        }
    }
    @Test func mixedProductAndDuplicateSkuResponsesFailClosed() async throws {
        let spec = ProductSpecification(
            id: 2, productID: 9, name: "白", priceYuan: 1, stock: 1, imageURLs: [])
        await #expect(throws: ProductDetailLoadFailure.invalidResponse) {
            try await CartProductVerifier(
                loader: CheckedProductSource(available: true, specs: [spec])
            ).check(productID: 1)
        }
        let valid = ProductSpecification(
            id: 2, productID: 1, name: "白", priceYuan: 1, stock: 1, imageURLs: [])
        await #expect(throws: ProductDetailLoadFailure.invalidResponse) {
            try await CartProductVerifier(
                loader: CheckedProductSource(available: true, specs: [valid, valid])
            ).check(productID: 1)
        }
    }
}
