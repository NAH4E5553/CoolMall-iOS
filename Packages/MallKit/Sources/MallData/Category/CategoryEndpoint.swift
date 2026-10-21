import Foundation
import MallCore

/// `POST goods/type/list` request identity: fixed empty body, no query, no
/// authorization header, no retry. Configuration validation mirrors the H0
/// endpoint rules so both services reject an invalid environment before I/O.
struct CategoryEndpoint {
    let url: URL
    let requestTimeout: TimeInterval

    init(environment: APIEnvironment) throws {
        guard
            environment.baseURL.scheme?.lowercased() == "https",
            let host = environment.baseURL.host, !host.isEmpty,
            environment.baseURL.absoluteString.hasSuffix("/"),
            environment.baseURL.query == nil,
            environment.baseURL.fragment == nil,
            environment.baseURL.user == nil,
            environment.baseURL.password == nil
        else { throw CategoryLoadFailure.invalidConfiguration }
        guard
            environment.requestTimeout > 0, environment.requestTimeout.isFinite,
            environment.resourceTimeout > 0, environment.resourceTimeout.isFinite
        else { throw CategoryLoadFailure.invalidConfiguration }
        guard
            let url = URL(string: "goods/type/list", relativeTo: environment.baseURL)?.absoluteURL,
            url.scheme?.lowercased() == "https", url.host != nil
        else { throw CategoryLoadFailure.invalidConfiguration }
        self.url = url
        self.requestTimeout = environment.requestTimeout
    }

    /// The captured production request: POST with an empty body. The reference
    /// client sends no content type for this bodyless POST; only Accept is set.
    func request() -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
