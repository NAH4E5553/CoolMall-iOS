import Foundation
@testable import MallImages
import Nuke
import SwiftUI
import Testing

@MainActor
struct ImagePipelineTests {
    private func make(
        _ loader: ImageTestLoader, namespace: String = UUID().uuidString, root: URL? = nil,
        disk: Int = 0
    ) throws -> MallImagePipeline {
        try MallImagePipeline(
            configuration: .init(diskLimitBytes: disk, cacheNamespace: namespace),
            cacheRoot: root, protocolClasses: nil, dataLoader: loader)
    }

    private func request(
        _ pipeline: MallImagePipeline, path: String = "/wide", width: CGFloat = 120,
        mode: ContentMode = .fill
    ) throws -> ImageRequest {
        try #require(
            pipeline.request(
                url: URL(string: "https://image-tests.invalid\(path)"),
                targetSize: CGSize(width: width, height: width / 2), scale: 2,
                contentMode: mode, isEnabled: true))
    }

    @Test func invalidConfigurationsFailBeforeTransport() throws {
        for name in ["", "../escape", "a/b", String(repeating: "a", count: 65), "中文"] {
            #expect(throws: (any Error).self) {
                try MallImagePipeline(configuration: .init(cacheNamespace: name))
            }
        }
        #expect(throws: (any Error).self) {
            try MallImagePipeline(configuration: .init(memoryLimitBytes: 0, cacheNamespace: "test"))
        }
        #expect(throws: (any Error).self) {
            try MallImagePipeline(configuration: .init(diskLimitBytes: -1, cacheNamespace: "test"))
        }
    }

    @Test func invalidMissingInactiveInputsMakeNoRequest() throws {
        let loader = ImageTestLoader(bytes: try imageBytes())
        let p = try make(loader)
        for url in [
            nil, URL(string: "http://image-tests.invalid/a"),
            URL(string: "https://user:secret@image-tests.invalid/a"), URL(string: "file:///tmp/a"),
        ] {
            #expect(
                p.request(
                    url: url, targetSize: CGSize(width: 10, height: 10), scale: 2,
                    contentMode: .fill, isEnabled: true) == nil)
        }
        for size in [
            CGSize.zero, CGSize(width: -1, height: 2), CGSize(width: CGFloat.infinity, height: 2),
        ] {
            #expect(
                p.request(
                    url: URL(string: "https://image-tests.invalid/a"), targetSize: size, scale: 2,
                    contentMode: .fill, isEnabled: true) == nil)
        }
        #expect(
            p.request(
                url: URL(string: "https://image-tests.invalid/a"),
                targetSize: CGSize(width: 10, height: 10), scale: 2, contentMode: .fill,
                isEnabled: false) == nil)
    }

    @Test func thumbnailDecodesLargeSourceAtTargetPixels() async throws {
        let loader = ImageTestLoader(bytes: try imageBytes())
        let p = try make(loader)
        let response = try await p.pipeline.imageTask(with: request(p)).response
        let cg = try #require(response.image.cgImage)
        #expect(cg.width == 240 && cg.height == 120)
        #expect(response.image.scale == 2)
        #expect(p.memoryCache.totalCost < 4096 * 2048 * 4)
        let larger = try await p.pipeline.imageTask(with: request(p, width: 240)).response
        #expect(larger.image.cgImage?.width == 480)
        #expect(larger.image.cgImage?.height == 240)
        #expect(await loader.requests.count == 2)  // no disk cache in this configuration
    }

    @Test func stableMemoryCacheAndSeparateFitFillIdentity() async throws {
        let p = try make(ImageTestLoader(bytes: try imageBytes()))
        let a = try request(p)
        _ = try await p.pipeline.imageTask(with: a).response
        let b = try await p.pipeline.imageTask(with: request(p)).response
        #expect(b.cacheType == .memory)
        var fit = try request(p, mode: .fit)
        fit.thumbnail = .init(
            size: CGSize(width: 120, height: 120), unit: .pixels, contentMode: .aspectFit)
        let decoded = try await p.pipeline.imageTask(with: fit).response
        #expect(decoded.image.cgImage?.width == 120)
        #expect(decoded.image.cgImage?.height == 60)
        #expect(p.pipeline.cache[fit] != nil)
        #expect(p.pipeline.cache[a] != nil)
        #expect(p.pipeline.cache[try request(p, path: "/changed")] == nil)
    }

    @Test func sharedWorkSurvivesOneSubscriberCancellation() async throws {
        let loader = ImageTestLoader(bytes: try imageBytes(), automatic: false)
        let p = try make(loader)
        let a = p.pipeline.imageTask(with: try request(p))
        let b = p.pipeline.imageTask(with: try request(p))
        try await awaitImageEvent { await loader.requests.count == 1 }
        a.cancel()
        await loader.finishAll()
        _ = try await b.response
        #expect(await loader.requests.count == 1)
        #expect(await loader.cancellations == 0)
        await #expect(throws: (any Error).self) { try await a.response }
    }

    @Test func lastSubscriberCancellationSuppressesLateTransport() async throws {
        let loader = ImageTestLoader(bytes: try imageBytes(), automatic: false)
        let p = try make(loader)
        let a = p.pipeline.imageTask(with: try request(p))
        try await awaitImageEvent { await loader.requests.count == 1 }
        a.cancel()
        try await awaitImageEvent { await loader.cancellations == 1 }
        await loader.finishAll()
        await #expect(throws: (any Error).self) { try await a.response }
        let b = p.pipeline.imageTask(with: try request(p, path: "/B"))
        try await awaitImageEvent { await loader.requests.count == 2 }
        await loader.finishAll()
        let result = try await b.response
        #expect(result.request.url?.path == "/B")
    }

    @Test func diskCacheRestoresAndNamespacesStayIsolated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = ImageTestLoader(bytes: try imageBytes())
        do {
            let first = try make(loader, namespace: "first", root: root, disk: 134_217_728)
            _ = try await first.pipeline.imageTask(with: request(first)).response
            first.diskCache?.flush()
            first.pipeline.invalidate()
        }
        let restored = try make(loader, namespace: "first", root: root, disk: 134_217_728)
        _ = try await restored.pipeline.imageTask(with: request(restored)).response
        #expect(await loader.requests.count == 1)
        let separate = try make(loader, namespace: "second", root: root, disk: 134_217_728)
        _ = try await separate.pipeline.imageTask(with: request(separate)).response
        #expect(await loader.requests.count == 2)
        let cache = try #require(restored.diskCache)
        cache.sizeLimit = 16
        cache.storeData(Data(repeating: 0, count: 1000), for: "eviction")
        cache.flush()
        cache.sweep()
        #expect(cache.totalSize <= 16)
    }

    @Test func diskInitializationFailureAndMemoryOnlyRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("file blocks directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = ImageTestLoader(bytes: try imageBytes())
        #expect(throws: (any Error).self) { try make(loader, root: root, disk: 100) }
        let p = try make(loader, root: root)
        #expect(p.diskCache == nil)
        #expect(p.memoryCache.costLimit == 33_554_432)
    }

    @Test func memoryLimitDeclinesOversizedEntriesWithoutBreakingDisplay() async throws {
        let loader = ImageTestLoader(bytes: try imageBytes())
        let p = try MallImagePipeline(
            configuration: .init(
                memoryLimitBytes: 1024, diskLimitBytes: 0, cacheNamespace: "small-memory"),
            cacheRoot: nil, protocolClasses: nil, dataLoader: loader)
        _ = try await p.pipeline.imageTask(with: request(p)).response
        #expect(p.memoryCache.totalCost <= 1024)
        #expect(p.pipeline.cache[try request(p)] == nil)
        _ = try await p.pipeline.imageTask(with: request(p)).response
        #expect(await loader.requests.count == 2)
    }

    @Test func differentThumbnailSubscribersShareTheOriginalDownload() async throws {
        let loader = ImageTestLoader(bytes: try imageBytes(), automatic: false)
        let p = try make(loader)
        let a = p.pipeline.imageTask(with: try request(p, width: 120))
        let b = p.pipeline.imageTask(with: try request(p, width: 240))
        try await awaitImageEvent { await loader.requests.count == 1 }
        await loader.finishAll()
        #expect(try await a.response.image.cgImage?.width == 240)
        #expect(try await b.response.image.cgImage?.width == 480)
        #expect(await loader.requests.count == 1)
    }

    @Test(arguments: [false, true]) func oldSuccessOrErrorAfterCancelCannotReplaceB(isError: Bool)
        async throws
    {
        let old = ImageTestLoader(bytes: try imageBytes(), automatic: false)
        let p = try make(old)
        let a = p.pipeline.imageTask(with: try request(p, path: "/A"))
        try await awaitImageEvent { await old.requests.count == 1 }
        a.cancel()
        try await awaitImageEvent { await old.cancellations == 1 }
        let b = p.pipeline.imageTask(with: try request(p, path: "/B"))
        try await awaitImageEvent { await old.requests.count == 2 }
        // Deliver B before the non-cooperative old A callback.
        await old.finish(path: "/B")
        let response = try await b.response
        await old.finish(path: "/A", error: isError ? URLError(.badServerResponse) : nil)
        await #expect(throws: (any Error).self) { try await a.response }
        #expect(response.request.url?.path == "/B")
        #expect(p.pipeline.cache[try request(p, path: "/B")] != nil)
    }

    @Test func configuredRedirectDelegateStripsHeadersAndRejectsPrivateOrHTTP() async throws {
        let p = try MallImagePipeline(
            configuration: .init(diskLimitBytes: 0, cacheNamespace: "redirect-test"),
            cacheRoot: nil, protocolClasses: [ImageTestURLProtocol.self])
        let loader = try #require(p.pipeline.configuration.dataLoader as? DataLoader)
        #expect(loader.session.configuration.urlCredentialStorage == nil)
        #expect(loader.session.configuration.httpCookieStorage == nil)
        #expect(loader.session.configuration.httpShouldSetCookies == false)
        #expect(loader.session.configuration.urlCache == nil)
        let policy = try #require(loader.delegate as? PublicImageTransportPolicy)
        let original = try #require(URL(string: "https://image-tests.invalid/original"))
        let response = try #require(
            HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil))
        for target in [
            "https://image-tests.invalid/next", "http://image-tests.invalid/next",
            "https://user:pass@image-tests.invalid/next",
        ] {
            let url = try #require(URL(string: target))
            var redirected = URLRequest(url: url)
            redirected.setValue("must-strip", forHTTPHeaderField: "Authorization")
            redirected.setValue("must-strip", forHTTPHeaderField: "Cookie")
            let (stream, continuation) = AsyncStream<URLRequest?>.makeStream()
            let task = loader.session.dataTask(with: original)  // deliberately never resumed
            policy.urlSession(
                loader.session, task: task, willPerformHTTPRedirection: response,
                newRequest: redirected
            ) { value in
                continuation.yield(value); continuation.finish()
            }
            var iterator = stream.makeAsyncIterator()
            let emitted = await iterator.next()
            if url.scheme == "https" && url.user == nil {
                let item = try #require(emitted)
                let clean = try #require(item)
                #expect(clean.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(clean.value(forHTTPHeaderField: "Cookie") == nil)
            } else {
                #expect(try #require(emitted) == nil)
            }
        }
    }

    @Test func realURLSessionHasNoCredentialsAndRejectsFailures() async throws {
        let p = try MallImagePipeline(
            configuration: .init(diskLimitBytes: 0, cacheNamespace: UUID().uuidString),
            cacheRoot: nil, protocolClasses: [ImageTestURLProtocol.self])
        _ = try await p.pipeline.imageTask(with: request(p)).response
        for path in ["/404", "/bad", "/offline", "/timeout"] {
            await #expect(throws: (any Error).self) {
                try await p.pipeline.imageTask(with: request(p, path: path)).response
            }
        }
    }
}
