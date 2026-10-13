#if DEBUG
    import Foundation
    import MallCore
    import MallData
    import MallImages
    import SwiftUI

    /// Sole owner of DEBUG-only observed transport counts, never homepage state.
    @MainActor
    final class ImageUITestMetrics: ObservableObject {
        @Published var starts = 0
        @Published var cancellations = 0
        @Published var homeCalls = 0
    }

    @MainActor
    struct ImageUITestSupport {
        static let metrics = ImageUITestMetrics()
        let pipeline: MallImagePipeline?

        init?(mode: HomeUITestSupport.FixtureMode?) {
            guard mode == .imageSuccess || mode == .imageFailure || mode == .imagePending else {
                return nil
            }
            do {
                pipeline = try MallImagePipeline(
                    configuration: .init(diskLimitBytes: 0, cacheNamespace: "image-ui-test"),
                    testingProtocolClasses: [ImageUITestURLProtocol.self])
            } catch {
                print("受控图片管线初始化失败")
                pipeline = nil
            }
        }
    }

    struct ImageUITestMetricsView: View {
        @ObservedObject private var metrics = ImageUITestSupport.metrics
        var body: some View {
            Text("图片请求：\(metrics.starts)；取消：\(metrics.cancellations)；首页读取：\(metrics.homeCalls)")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home.image.metrics")
        }
    }

    private final class ImageUITestURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "image-tests.invalid"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Task { @MainActor in ImageUITestSupport.metrics.starts += 1 }
            guard let url = request.url else { return }
            if url.path == "/pending" { return }
            guard
                let response = HTTPURLResponse(
                    url: url, statusCode: url.path == "/failure" ? 404 : 200,
                    httpVersion: nil, headerFields: ["Content-Type": "image/png"])
            else { return }
            // Self-authored 32x16 PNG, matching the module-test resource.
            guard
                let bytes = Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAHUlEQVR4nGOQS3lGU8QwasGoBaMWjFowasFQsAAAddvQHxXJaVoAAAAASUVORK5CYII="
                )
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {
            // URLSession also calls stopLoading after completed responses.
            // Only the deliberately unfinished request is cancellation evidence.
            guard request.url?.path == "/pending" else { return }
            Task { @MainActor in ImageUITestSupport.metrics.cancellations += 1 }
        }
    }

    /// Same HomeSnapshot contract, only first banner URL is synthetic. Refreshed
    /// pending/failure A changes to B; no real homepage/CDN HTTP occurs.
    actor ImageHomeService: HomeLoading {
        let mode: HomeUITestSupport.FixtureMode
        private var calls = 0
        init(mode: HomeUITestSupport.FixtureMode) { self.mode = mode }
        func loadHome() async throws -> HomeSnapshot {
            calls += 1
            let call = calls
            await MainActor.run { ImageUITestSupport.metrics.homeCalls += 1 }
            let base = try await FixtureHomeService().loadHome()
            let path: String
            switch mode {
            case .imagePending where call == 1: path = "/pending"
            case .imageFailure where call == 1: path = "/failure"
            default: path = call == 1 ? "/success-a" : "/success-b"
            }
            let banners = base.banners.enumerated().map { index, banner in
                HomeBanner(
                    id: banner.id, description: banner.description,
                    imageURL: index == 0 && !(mode == .imageSuccess && call >= 3)
                        ? URL(string: "https://image-tests.invalid\(path)") : nil)
            }
            return HomeSnapshot(
                banners: banners, categories: base.categories,
                allCategories: base.allCategories, featured: base.featured,
                recommendations: base.recommendations, goods: base.goods, coupons: base.coupons)
        }
    }
#endif
