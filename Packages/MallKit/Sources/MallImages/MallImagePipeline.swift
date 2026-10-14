import Foundation
import Nuke
import SwiftUI

/// App-owned image adapter. SDK caches/tasks stay internal; no business credentials.
@MainActor
public final class MallImagePipeline {
    let pipeline: ImagePipeline
    let memoryCache: ImageCache
    let diskCache: DataCache?
    let configuration: MallImageConfiguration
    // Nuke's proxy holds its delegate weakly; retain the transport policy here.
    private let transportPolicy: PublicImageTransportPolicy

    public convenience init(configuration: MallImageConfiguration) throws {
        try self.init(configuration: configuration, cacheRoot: nil, protocolClasses: nil)
    }

    #if DEBUG
        /// Event-controlled App UI-test source; absent from Release.
        /// Protocols run directly, without URLSession timers. Production and
        /// internal URLSession transport tests retain the real 10/30s deadlines.
        public convenience init(
            configuration: MallImageConfiguration, testingProtocolClasses: [URLProtocol.Type]
        ) throws {
            try self.init(
                configuration: configuration, cacheRoot: nil,
                protocolClasses: nil,
                dataLoader: ControlledImageProtocolLoader(protocolClasses: testingProtocolClasses))
        }
    #endif

    /// Internal test seam; public callers cannot change the production transport.
    init(
        configuration: MallImageConfiguration, cacheRoot: URL?,
        protocolClasses: [AnyClass]?, dataLoader: (any DataLoading)? = nil
    ) throws {
        try configuration.validate()
        self.configuration = configuration
        memoryCache = ImageCache(costLimit: configuration.memoryLimitBytes)
        if configuration.diskLimitBytes == 0 {
            diskCache = nil
        } else {
            let cache: DataCache
            if let cacheRoot {
                cache = try DataCache(
                    path: cacheRoot.appendingPathComponent(configuration.cacheNamespace))
            } else {
                cache = try DataCache(name: "coolmall-images-\(configuration.cacheNamespace)")
            }
            cache.sizeLimit = configuration.diskLimitBytes
            diskCache = cache
        }
        let session = URLSessionConfiguration.ephemeral
        session.httpShouldSetCookies = false
        session.httpCookieStorage = nil
        session.urlCredentialStorage = nil
        session.urlCache = nil
        session.requestCachePolicy = .reloadIgnoringLocalCacheData
        session.timeoutIntervalForRequest = 10
        session.timeoutIntervalForResource = 30
        if let protocolClasses { session.protocolClasses = protocolClasses }
        let loader = DataLoader(configuration: session)
        let policy = PublicImageTransportPolicy()
        loader.delegate = policy
        transportPolicy = policy
        var options = ImagePipeline.Configuration()
        options.dataLoader = dataLoader ?? loader
        options.imageCache = memoryCache
        options.dataCache = diskCache
        options.dataCachePolicy = .storeOriginalData
        options.isProgressiveDecodingEnabled = false
        options.isResumableDataEnabled = false
        options.isLocalResourcesSupportEnabled = false
        pipeline = ImagePipeline(configuration: options)
    }

    func request(
        url: URL?, targetSize: CGSize, scale: CGFloat, contentMode: ContentMode,
        isEnabled: Bool
    ) -> ImageRequest? {
        guard isEnabled, MallImageConfiguration.allows(url),
            targetSize.width.isFinite, targetSize.height.isFinite,
            scale.isFinite, targetSize.width > 0, targetSize.height > 0, scale > 0
        else { return nil }
        let width = ceil(targetSize.width * scale)
        let height = ceil(targetSize.height * scale)
        guard width.isFinite, height.isFinite, width <= CGFloat(Int32.max),
            height <= CGFloat(Int32.max)
        else { return nil }
        var request = ImageRequest(url: url)
        request.scale = Float(scale)
        request.thumbnail = .init(
            size: CGSize(width: width, height: height), unit: .pixels,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit)
        return request
    }
}

/// Redirects remain public HTTPS, with no inherited headers or credential lookup.
final class PublicImageTransportPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard MallImageConfiguration.allows(request.url) else {
            completionHandler(nil)
            return
        }
        var clean = request
        clean.setValue(nil, forHTTPHeaderField: "Authorization")
        clean.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(clean)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler:
            @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}

#if DEBUG
    /// DEBUG fixture bridge only. Nuke owns and cancels this returned ticket;
    /// UI actions never synthesize transport cancellation. No network fallback.
    struct ControlledImageProtocolLoader: DataLoading {
        let protocolClasses: [URLProtocol.Type]

        func loadData(
            with request: URLRequest,
            didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
            completion: @escaping @Sendable (Error?) -> Void
        ) -> any Cancellable {
            let ticket = ControlledImageProtocolTicket(
                data: didReceiveData, completion: completion)
            ticket.start(request, protocolClasses: protocolClasses)
            return ticket
        }
    }

    /// One MainActor owns the protocol, response and single terminal state.
    /// SDK callbacks enqueue Sendable values on the serial main queue, preserving
    /// response/data/finish ordering even for synchronous source callbacks.
    @MainActor
    final class ControlledImageProtocolTicket: NSObject, URLProtocolClient, Cancellable {
        private(set) var source: URLProtocol?
        private var response: URLResponse?
        private var ended = false
        private let data: @Sendable (Data, URLResponse) -> Void
        private let completion: @Sendable (Error?) -> Void

        nonisolated init(
            data: @escaping @Sendable (Data, URLResponse) -> Void,
            completion: @escaping @Sendable (Error?) -> Void
        ) {
            self.data = data
            self.completion = completion
        }

        nonisolated func start(_ request: URLRequest, protocolClasses: [URLProtocol.Type]) {
            DispatchQueue.main.async {
                guard !self.ended else { return }
                guard let type = protocolClasses.first(where: { $0.canInit(with: request) }) else {
                    self.finish(URLError(.unsupportedURL))
                    return
                }
                let source = type.init(request: request, cachedResponse: nil, client: self)
                self.source = source
                source.startLoading()
            }
        }

        nonisolated func cancel() {
            DispatchQueue.main.async {
                guard !self.ended else { return }
                self.ended = true
                let source = self.source
                self.source = nil
                source?.stopLoading()
            }
        }

        private func finish(_ error: Error?) {
            guard !ended else { return }
            ended = true
            let source = source
            self.source = nil
            completion(error)
            source?.stopLoading()
        }

        nonisolated func urlProtocol(
            _ protocol: URLProtocol, didReceive response: URLResponse,
            cacheStoragePolicy policy: URLCache.StoragePolicy
        ) {
            DispatchQueue.main.async {
                guard !self.ended else { return }
                if let error = DataLoader.validate(response: response) {
                    self.finish(error)
                } else {
                    self.response = response
                }
            }
        }

        nonisolated func urlProtocol(_ protocol: URLProtocol, didLoad bytes: Data) {
            DispatchQueue.main.async {
                guard !self.ended, let response = self.response else { return }
                self.data(bytes, response)
            }
        }

        nonisolated func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
            DispatchQueue.main.async { self.finish(nil) }
        }

        nonisolated func urlProtocol(_ protocol: URLProtocol, didFailWithError error: Error) {
            DispatchQueue.main.async { self.finish(error) }
        }

        nonisolated func urlProtocol(
            _ protocol: URLProtocol, wasRedirectedTo request: URLRequest,
            redirectResponse: URLResponse
        ) { urlProtocol(`protocol`, didFailWithError: URLError(.unsupportedURL)) }
        nonisolated func urlProtocol(
            _ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse
        ) {}
        nonisolated func urlProtocol(
            _ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge
        ) {
            urlProtocol(`protocol`, didFailWithError: URLError(.userAuthenticationRequired))
        }
        nonisolated func urlProtocol(
            _ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge
        ) {}
    }
#endif
