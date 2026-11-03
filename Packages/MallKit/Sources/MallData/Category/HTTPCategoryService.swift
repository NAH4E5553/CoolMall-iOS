import Foundation
import MallCore

/// CATEGORY-01 production read service (A-GOODS-01). The App creates one
/// instance and injects it as `any CategoryLoading`; it keeps no page state,
/// offers no retry and never touches UI types.
public final class HTTPCategoryService: CategoryLoading, Sendable {
    private let environment: APIEnvironment
    private let client: CategoryAPIClient

    /// Test assembly point: a controlled transport exercises the exact
    /// production request/decoding path via @testable.
    init(environment: APIEnvironment, transport: any CategoryHTTPTransport) {
        self.environment = environment
        self.client = CategoryAPIClient(transport: transport)
    }

    public convenience init(environment: APIEnvironment) {
        self.init(
            environment: environment,
            transport: URLSessionTransport(resourceTimeout: environment.resourceTimeout)
        )
    }

    public func loadCategories() async throws -> [CategoryNode] {
        let data = try await client.bodyData(environment: environment)
        return try CategoryEnvelopeDecoder.categories(from: data)
    }
}
