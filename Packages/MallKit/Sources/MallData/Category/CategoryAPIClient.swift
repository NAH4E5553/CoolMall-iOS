import Foundation
import MallCore

/// Sends the fixed category request and interprets HTTP/transport failures with
/// the same precedence as H0: HTTP status first, cancellation propagated (never
/// a page failure), timeout/network mapped without leaking raw transport text.
final class CategoryAPIClient: Sendable {
    private let transport: any CategoryHTTPTransport

    init(transport: any CategoryHTTPTransport) {
        self.transport = transport
    }

    func bodyData(environment: APIEnvironment) async throws -> Data {
        let endpoint: CategoryEndpoint
        do { endpoint = try CategoryEndpoint(environment: environment) } catch {
            throw CategoryLoadFailure.invalidConfiguration
        }
        do {
            let (data, response) = try await transport.send(endpoint.request())
            guard let http = response as? HTTPURLResponse else {
                throw CategoryLoadFailure.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw CategoryLoadFailure.httpStatus(http.statusCode)
            }
            return data
        } catch let failure as CategoryLoadFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw CancellationError() }
            if urlError.code == .timedOut { throw CategoryLoadFailure.timeout }
            throw CategoryLoadFailure.networkUnavailable
        } catch {
            throw CategoryLoadFailure.networkUnavailable
        }
    }
}
