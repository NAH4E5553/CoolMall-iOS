import Foundation
import MallCore

/// GET page/home — the only endpoint H0 v0.2 consumes (A-PAGE-01).
/// No query, no body, no authorization header, no automatic retry.
struct Endpoint {
    let url: URL
    let requestTimeout: TimeInterval

    init(environment: APIEnvironment) throws {
        // The trailing-slash check uses absoluteString: URL.path drops the
        // trailing slash on this toolchain, and relative joining needs it.
        guard
            environment.baseURL.scheme?.lowercased() == "https",
            let host = environment.baseURL.host, !host.isEmpty,
            environment.baseURL.absoluteString.hasSuffix("/"),
            environment.baseURL.query == nil,
            environment.baseURL.fragment == nil,
            environment.baseURL.user == nil,
            environment.baseURL.password == nil
        else { throw HomeLoadFailure.invalidConfiguration }
        guard
            environment.requestTimeout > 0, environment.requestTimeout.isFinite,
            environment.resourceTimeout > 0, environment.resourceTimeout.isFinite
        else { throw HomeLoadFailure.invalidConfiguration }
        guard let url = URL(string: "page/home", relativeTo: environment.baseURL)?.absoluteURL,
            url.scheme?.lowercased() == "https", url.host != nil
        else { throw HomeLoadFailure.invalidConfiguration }
        self.url = url
        self.requestTimeout = environment.requestTimeout
    }
}
