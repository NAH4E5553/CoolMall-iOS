import Foundation
import MallCore

/// H0 v0.2 production home read service. The App creates one instance and
/// injects it as `any HomeLoading`; it keeps no page state, offers no retry
/// and never touches UI types.
public final class HTTPHomeService: HomeLoading, Sendable {
    private let environment: APIEnvironment
    private let client: APIClient

    /// Test assembly point: a controlled transport exercises the exact
    /// production request/decoding path via @testable.
    init(environment: APIEnvironment, transport: any HTTPTransport) {
        self.environment = environment
        self.client = APIClient(transport: transport)
    }

    public convenience init(environment: APIEnvironment) {
        self.init(
            environment: environment,
            transport: URLSessionTransport(resourceTimeout: environment.resourceTimeout)
        )
    }

    public func loadHome() async throws -> HomeSnapshot {
        let data = try await client.bodyData(environment: environment)
        return try HomeEnvelopeDecoder.snapshot(from: data)
    }
}
