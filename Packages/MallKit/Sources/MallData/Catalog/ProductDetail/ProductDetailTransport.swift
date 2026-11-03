import Foundation
import MallCore

/// Detail's GET/POST request boundary; the existing Home GET contract is unchanged.
protocol ProductDetailTransport: Sendable {
    func send(request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSessionTransport: ProductDetailTransport {
    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        try await sendProductRequest(request)
    }
}

extension APIClient {
    /// Request-based read path within the existing client, not a second client
    /// platform. The service supplies its anonymous, ephemeral transport.
    static func productBodyData(
        for request: URLRequest, using transport: any ProductDetailTransport
    )
        async throws -> Data
    {
        do {
            try Task.checkCancellation()
            let (data, response) = try await transport.send(request: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw ProductDetailLoadFailure.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw ProductDetailLoadFailure.httpStatus(http.statusCode)
            }
            return data
        } catch let failure as ProductDetailLoadFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut
                ? ProductDetailLoadFailure.timeout : ProductDetailLoadFailure.networkUnavailable
        } catch { throw ProductDetailLoadFailure.networkUnavailable }
    }
}
