import Foundation
import MallCore
@testable import MallData
import Testing

/// AT-HOME-01-10: the real URLSession adapter behind URLSessionTransport,
/// exercised through URLProtocol. The echo protocol reflects the request it
/// received as JSON (stateless, concurrency-safe); the slow protocol delays
/// its response long enough to cover request timeout and task cancellation.
struct HomeTransportTests {
    static let base = URL(string: "https://mall.dusksnow.top/app/")!

    // MARK: stateless URLProtocol stubs

    final class EchoRequestURLProtocol: URLProtocol {
        struct Echo: Decodable {
            let url: String
            let method: String
            let accept: String
            let authorization: String
            let cookie: String
            let timeout: String
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let echo: [String: String] = [
                "url": request.url?.absoluteString ?? "",
                "method": request.httpMethod ?? "",
                "accept": request.value(forHTTPHeaderField: "Accept") ?? "",
                "authorization": request.value(forHTTPHeaderField: "Authorization") != nil
                    ? "yes" : "no",
                "cookie": request.value(forHTTPHeaderField: "Cookie") != nil ? "yes" : "no",
                "timeout": String(format: "%.1f", request.timeoutInterval),
            ]
            let body: Data
            do { body = try JSONEncoder().encode(echo) } catch { body = Data() }
            guard
                let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    final class SlowURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            // Blocks this session's worker thread long enough for the client
            // timeout (0.5s) or an explicit cancel to win deterministically.
            Thread.sleep(forTimeInterval: 2.0)
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"code":1000,"data":{}}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    static func echoSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EchoRequestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func slowService() -> HTTPHomeService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowURLProtocol.self]
        let transport = URLSessionTransport(session: URLSession(configuration: configuration))
        return HTTPHomeService(
            environment: APIEnvironment(baseURL: base, requestTimeout: 0.5),
            transport: transport
        )
    }

    // MARK: request construction

    @Test func requestConstructionUsesExactGETWithoutAuthOrCookies() async throws {
        let endpoint = try Endpoint(environment: APIEnvironment(baseURL: Self.base))
        let transport = URLSessionTransport(session: Self.echoSession())
        let (data, response) = try await transport.send(
            url: endpoint.url, timeout: endpoint.requestTimeout)

        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        let echo = try JSONDecoder().decode(EchoRequestURLProtocol.Echo.self, from: data)
        #expect(echo.url == "https://mall.dusksnow.top/app/page/home")
        #expect(echo.method == "GET")
        #expect(echo.accept == "application/json")
        #expect(echo.authorization == "no")
        #expect(echo.cookie == "no")
        #expect(echo.timeout == "10.0")
    }

    // MARK: timeout mapping

    @Test func requestTimeoutMapsToTimeoutFailure() async {
        let service = Self.slowService()
        await #expect(throws: HomeLoadFailure.timeout) {
            _ = try await service.loadHome()
        }
    }

    // MARK: cancellation propagation

    @Test func taskCancellationPropagatesAsCancellationError() async throws {
        let service = Self.slowService()
        let task = Task { try await service.loadHome() }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation, got success")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
    }

    // MARK: R-HOME-01-05 production session configuration

    @Test func productionConfigurationDisablesCookieCredentialAndCacheStorage() {
        // The actual production configuration, not a test-injected session:
        // no cookie storage, no credential storage, no URL cache.
        let configuration = URLSessionTransport.makeProductionConfiguration(resourceTimeout: 30)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForResource == 30)
    }
}
