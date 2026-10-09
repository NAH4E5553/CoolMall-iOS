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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = resourceTimeout
        self.init(session: URLSession(configuration: configuration))
    }

    func send(url: URL, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }
}
