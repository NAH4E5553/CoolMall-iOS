import Foundation

/// Production transport (H0 execution contract): ephemeral URLSession, no
/// cookie/credential storage, business URL caching disabled. The request
/// timeout rides on each URLRequest; the resource timeout caps the session.
final class URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    convenience init(resourceTimeout: TimeInterval) {
        self.init(
            session: URLSession(
                configuration: Self.makeProductionConfiguration(resourceTimeout: resourceTimeout)))
    }

    /// H0 production session configuration (R-HOME-01-05): ephemeral with no
    /// cookie storage, no credential storage, and business URL caching off.
    /// Extracted so tests can verify the actual production values.
    static func makeProductionConfiguration(resourceTimeout: TimeInterval)
        -> URLSessionConfiguration
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    func send(url: URL, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }
}
