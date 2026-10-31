import Foundation

/// Request-level transport used only by the category POST. Kept separate from
/// the H0 `HTTPTransport` GET method so the verified home request path is
/// untouched; the production URLSession adapter is the same object.
protocol CategoryHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSessionTransport: CategoryHTTPTransport {}
