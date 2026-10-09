import Foundation
import MallCore

/// Sends the fixed request and interprets transport errors (H0): HTTP first,
/// then the envelope layer (HomeEnvelopeDecoder). Fresh JSON decoders per
/// call; no shared mutable decoding state.
final class APIClient: Sendable {
    private let transport: any HTTPTransport

    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// Performs the request and returns the HTTP 2xx body; maps transport
    /// errors to HomeLoadFailure, cancellation to CancellationError.
    func bodyData(environment: APIEnvironment) async throws -> Data {
        let endpoint: Endpoint
        do { endpoint = try Endpoint(environment: environment) } catch {
            throw HomeLoadFailure.invalidConfiguration
        }
        do {
            let (data, response) = try await transport.send(
                url: endpoint.url, timeout: endpoint.requestTimeout
            )
            guard let http = response as? HTTPURLResponse else {
                throw HomeLoadFailure.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw HomeLoadFailure.httpStatus(http.statusCode)
            }
            return data
        } catch let failure as HomeLoadFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw CancellationError() }
            if urlError.code == .timedOut { throw HomeLoadFailure.timeout }
            throw HomeLoadFailure.networkUnavailable
        } catch {
            throw HomeLoadFailure.networkUnavailable
        }
    }
}
