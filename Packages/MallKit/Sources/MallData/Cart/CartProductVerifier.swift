import MallCore

/// Reuses actual catalog reads; there is no invented server cart endpoint.
public struct CartProductVerifier: CartProductChecking {
    private let loader: any ProductDetailLoading
    public init(loader: any ProductDetailLoading) { self.loader = loader }
    public func check(productID: Int64) async throws -> CartProductCheck {
        let detail = try await loader.loadDetail(productID: productID)
        try Task.checkCancellation()
        guard detail.id == productID else { throw ProductDetailLoadFailure.invalidResponse }
        guard detail.isAvailable else {
            return .init(productID: productID, isAvailable: false, quotes: [])
        }
        let specifications = try await loader.loadSpecifications(productID: productID)
        try Task.checkCancellation()
        guard Set(specifications.map(\.id)).count == specifications.count,
            specifications.allSatisfy({ $0.productID == productID && $0.id > 0 && $0.stock >= 0 })
        else { throw ProductDetailLoadFailure.invalidResponse }
        let quotes = try specifications.map {
            CartQuote(
                productID: productID, specificationID: $0.id, title: detail.title,
                specification: $0.name, imageURL: $0.imageURLs.first ?? detail.imageURLs.first,
                price: try CartMoney(yuan: $0.priceYuan), stock: $0.stock)
        }
        return .init(productID: productID, isAvailable: true, quotes: quotes)
    }
}
