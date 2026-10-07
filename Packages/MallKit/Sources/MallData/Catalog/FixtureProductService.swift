import Foundation
import MallCore

/// Packaged F0 fixture, not an HTTP response schema. Used by App composition and previews.
public struct FixtureProductService: ProductLoading {
    public init() {}
    public func product(id: Int64) async throws -> Product {
        try Task.checkCancellation()
        guard let url = Bundle.module.url(forResource: "product", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let dto = try JSONDecoder().decode(FixtureProductDTO.self, from: Data(contentsOf: url))
        guard dto.id == id else { throw FixtureError.notFound }
        try Task.checkCancellation()
        return Product(id: dto.id, title: dto.title)
    }
}

struct FixtureProductDTO: Decodable { let id: Int64; let title: String }
enum FixtureError: Error { case missingResource; case notFound }
