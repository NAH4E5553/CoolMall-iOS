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
        /// Explicitly approved App UI-test assembly; absent from Release.
        public convenience init(
            configuration: MallImageConfiguration, testingProtocolClasses: [URLProtocol.Type]
        ) throws {
            try self.init(
                configuration: configuration, cacheRoot: nil,
                protocolClasses: testingProtocolClasses)
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
