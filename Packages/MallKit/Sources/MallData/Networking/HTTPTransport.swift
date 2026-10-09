import Foundation

/// Internal transport boundary. Production uses URLSessionTransport; tests
/// inject a controlled stub or a URLProtocol-backed session.
protocol HTTPTransport: Sendable {
    func send(url: URL, timeout: TimeInterval) async throws -> (Data, URLResponse)
}
