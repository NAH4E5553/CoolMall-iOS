import Foundation
import Nuke
import Testing

/// Per-test actor gates the actual Nuke transport callbacks; no shared handlers.
actor ImageTestLoader: DataLoading {
    struct Pending: Sendable {
        let request: URLRequest
        let data: @Sendable (Data, URLResponse) -> Void
        let completion: @Sendable (Error?) -> Void
    }
    struct Ticket: Cancellable {
        let owner: ImageTestLoader
        let id: UUID
        func cancel() { Task { await owner.cancel(id) } }
    }
    private var pending: [UUID: Pending] = [:]
    private(set) var requests: [URLRequest] = []
    private(set) var cancellations = 0
    let bytes: Data
    let automatic: Bool
    let status: Int

    init(bytes: Data, automatic: Bool = true, status: Int = 200) {
        self.bytes = bytes
        self.automatic = automatic
        self.status = status
    }

    nonisolated func loadData(
        with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let id = UUID()
        let input = Pending(request: request, data: didReceiveData, completion: completion)
        Task { await start(id, input) }
        return Ticket(owner: self, id: id)
    }

    private func start(_ id: UUID, _ input: Pending) {
        requests.append(input.request)
        pending[id] = input
        if automatic { finish(id, error: nil) }
    }

    private func cancel(_ id: UUID) {
        cancellations += 1
        // Intentionally keep the callback: a non-cooperative old transport may
        // complete after cancellation. Nuke must suppress the disposed observer.
    }

    func finishAll(error: (any Error)? = nil) {
        for id in Array(pending.keys) { finish(id, error: error) }
    }

    func finish(path: String, error: (any Error)? = nil) {
        for (id, input) in pending where input.request.url?.path == path {
            finish(id, error: error)
        }
    }

    private func finish(_ id: UUID, error: (any Error)?) {
        guard let input = pending.removeValue(forKey: id), let url = input.request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { return }
        if let error {
            input.completion(error)
        } else {
            input.data(bytes, response)
            input.completion(nil)
        }
    }
}

func imageBytes(_ name: String = "wide") throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "png"))
    return try Data(contentsOf: url)
}

func awaitImageEvent(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        try #require(clock.now < deadline, "image event deadline")
        try await Task.sleep(for: .milliseconds(2))
    }
}

/// Stateless URLSession adapter verification: reject headers; request path selects
/// success/HTTP/bad-byte/transport failure. Each session has its own instance.
final class ImageTestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.value(forHTTPHeaderField: "Authorization") == nil,
            request.value(forHTTPHeaderField: "Cookie") == nil, let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }
        if url.path == "/offline" || url.path == "/timeout" {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(
                    url.path == "/offline" ? .notConnectedToInternet : .timedOut))
            return
        }
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: url.path == "/404" ? 404 : 200, httpVersion: nil,
                headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        do {
            let bytes = url.path == "/bad" ? Data("bad image".utf8) : try imageBytes()
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
