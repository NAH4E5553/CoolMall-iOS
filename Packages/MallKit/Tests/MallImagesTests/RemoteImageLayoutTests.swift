import Foundation
@testable import MallImages
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct RemoteImageLayoutTests {
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
