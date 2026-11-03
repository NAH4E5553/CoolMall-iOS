import Foundation
@testable import MallImages
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct RemoteImageLayoutTests {
    @Test func navigationPauseKeepsLoadedPixelsEvenAfterMemoryEvictionAndRejectsOldURL()
        async throws
    {
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).pngData {
            context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }
        let transport = ImageTestLoader(bytes: bytes)
        let pipeline = try MallImagePipeline(
            configuration: .init(diskLimitBytes: 0, cacheNamespace: UUID().uuidString),
            cacheRoot: nil, protocolClasses: nil, dataLoader: transport)
        let first = try #require(URL(string: "https://image-tests.invalid/first"))
        let second = try #require(URL(string: "https://image-tests.invalid/second"))
        var applied: Bool?
        func view(_ enabled: Bool, url: URL) -> ImageRetentionHarness {
            ImageRetentionHarness(url: url, pipeline: pipeline, enabled: enabled) { applied = $0 }
        }
        let host = UIHostingController(rootView: view(true, url: first))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<1000 { if rendersRed(host.view) { break }; await Task.yield() }
        #expect(rendersRed(host.view))
        pipeline.memoryCache.removeAll()
        applied = nil; host.rootView = view(false, url: first)
        for _ in 0..<1000 { if applied == false { break }; await Task.yield() }
        #expect(applied == false && rendersRed(host.view))
        applied = nil; host.rootView = view(true, url: first)
        for _ in 0..<1000 { if applied == true { break }; await Task.yield() }
        #expect(applied == true && rendersRed(host.view))
        #expect(await transport.requests.count == 1)
        applied = nil; host.rootView = view(false, url: second)
        for _ in 0..<1000 { if applied == false { break }; await Task.yield() }
        #expect(applied == false && !rendersRed(host.view))
        #expect(await transport.requests.count == 1)
        host.rootView = view(true, url: second)
        for _ in 0..<1000 { if rendersRed(host.view) { break }; await Task.yield() }
        #expect(rendersRed(host.view))
        #expect(await transport.requests.count == 2)
    }

    private func rendersRed(_ view: UIView) -> Bool {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { _ in
            view.drawHierarchy(
                in: CGRect(x: 0, y: 0, width: 120, height: 120), afterScreenUpdates: true)
        }
        guard let source = image.cgImage else { return false }
        var bytes = [UInt8](repeating: 0, count: 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
        }
        return rendered && bytes[0] > 180 && bytes[1] < 60 && bytes[2] < 60
    }

    @Test(arguments: [false, true])
    func naturalImageUsesSourceRatioWhileDefaultRemainsFixed(_ tall: Bool) async throws {
        let sourceSize = tall ? CGSize(width: 100, height: 300) : CGSize(width: 300, height: 100)
        let bytes = UIGraphicsImageRenderer(size: sourceSize).pngData { context in
            UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: sourceSize))
        }
        let pipeline = try MallImagePipeline(
            configuration: .init(diskLimitBytes: 0, cacheNamespace: UUID().uuidString),
            cacheRoot: nil, protocolClasses: nil, dataLoader: ImageTestLoader(bytes: bytes))
        let url = URL(string: "https://image-tests.invalid/ratio")!
        let request = try #require(
            pipeline.request(
                url: url, targetSize: CGSize(width: 120, height: 120), scale: 1,
                contentMode: .fill, isEnabled: true))
        _ = try await pipeline.pipeline.imageTask(with: request).response
        let view = RemoteImage(
            url: url, targetSize: CGSize(width: 120, height: 120),
            contentMode: .fit, pipeline: pipeline,
            preservesIntrinsicAspectRatio: true
        )
        .environment(\.displayScale, 1)
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 800))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let expected = 120 * sourceSize.height / sourceSize.width
        var measured: CGFloat = 0
        for _ in 0..<1000 {
            host.view.layoutIfNeeded()
            measured = host.sizeThatFits(in: CGSize(width: 120, height: 1000)).height
            if abs(measured - expected) < 1 { break }
            await Task.yield()
        }
        #expect(abs(measured - expected) < 1)
        let fixed = UIHostingController(
            rootView:
                RemoteImage(
                    url: nil, targetSize: CGSize(width: 120, height: 120), pipeline: pipeline))
        #expect(abs(fixed.sizeThatFits(in: CGSize(width: 120, height: 1000)).height - 120) < 1)
    }
}

@MainActor private struct ImageRetentionHarness: View {
    let url: URL
    let pipeline: MallImagePipeline
    let enabled: Bool
    let applied: @MainActor (Bool) -> Void
    var body: some View {
        RemoteImage(
            url: url, targetSize: CGSize(width: 120, height: 120), pipeline: pipeline,
            isEnabled: enabled
        )
        .environment(\.displayScale, 1)
        .onChange(of: enabled) { _, value in applied(value) }
        .onChange(of: url) { _, _ in applied(enabled) }
    }
}
