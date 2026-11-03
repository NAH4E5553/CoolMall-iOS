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
        @Published var timeouts = 0
        @Published var lateResponses = 0
        @Published var pendingPastDeadline = false
        var timeoutCommand: UInt64 = 0
        var lateCommand: UInt64 = 0
        @Published var urlStarts: [String: Int] = [:]
        @Published var urlCancellations: [String: Int] = [:]
        @Published var lateAttempts = 0

        func reset() {
            starts = 0
            cancellations = 0
            homeCalls = 0
            timeouts = 0
            lateResponses = 0
            pendingPastDeadline = false
            timeoutCommand = 0
            lateCommand = 0
            urlStarts = [:]
            urlCancellations = [:]
            lateAttempts = 0
        }
    }

    @MainActor
    struct ImageUITestSupport {
        static let metrics = ImageUITestMetrics()
        let pipeline: MallImagePipeline?

        init?(mode: HomeUITestSupport.FixtureMode?) {
            guard
                mode == .couponMany || mode == .imageSuccess || mode == .imageFailure
                    || mode == .imagePending
                    || mode == .bannerSingle || mode == .bannerMultiple || mode == .bannerReconcile
                    || mode == .bannerRefreshFailure || mode == .bannerPending
            else {
                return nil
            }
            Self.metrics.reset()
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
        var compact = false
        @ObservedObject private var metrics = ImageUITestSupport.metrics
        var body: some View {
            VStack {
                Text("图片请求：\(metrics.starts)；取消：\(metrics.cancellations)；首页读取：\(metrics.homeCalls)")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.image.metrics")
                Text("超时：\(metrics.timeouts)；旧响应：\(metrics.lateResponses)")
                    .font(.caption)
                    .accessibilityIdentifier("home.image.endings")
                if metrics.pendingPastDeadline {
                    Text("挂起超过10秒").accessibilityIdentifier("home.image.pending-aged")
                }
                if !compact {
                    HStack {
                        Button("图片超时") { metrics.timeoutCommand += 1 }
                            .accessibilityIdentifier("home.image.timeout")
                        Button("返回旧图") { metrics.lateCommand += 1 }
                            .accessibilityIdentifier("home.image.release-old")
                    }
                    if !metrics.urlStarts.isEmpty {
                        Text(
                            metrics.urlStarts.keys.sorted().map { key in
                                "\(key)=\(metrics.urlStarts[key, default: 0])/\(metrics.urlCancellations[key, default: 0])"
                            }.joined(separator: "；") + "；迟到尝试：\(metrics.lateAttempts)"
                        )
                        .font(.caption2).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home.image.urlMetrics")
                    }
                }
            }
        }
    }

    /// Each source has one UUID and terminal reason protected by its lock.
    /// Timer-target fixture events retain Foundation's callback contract;
    /// only immutable observations cross to MainActor metrics. The DEBUG bridge
    /// invokes source lifecycle on its serial main queue, without URLSession.
    private final class ImageUITestURLProtocol: URLProtocol {
        private enum End { case success, failure, timeout, cancellation }
        private let lock = NSRecursiveLock()
        private let id = UUID()
        private var end: End?
        private var ageTimer: Timer?
        private var startedAt: TimeInterval = 0
        private var timeoutCommand: UInt64 = 0
        private var lateCommand: UInt64 = 0
        private var ageRecorded = false

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "image-tests.invalid"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            lock.lock()
            defer { lock.unlock() }
            let path = request.url?.path ?? ""
            Task { @MainActor in
                ImageUITestSupport.metrics.starts += 1
                if path.hasPrefix("/banner-") {
                    ImageUITestSupport.metrics.urlStarts[path, default: 0] += 1
                }
            }
            guard let url = request.url else { return }
            if url.path == "/pending" || url.path == "/banner-pending-a" {
                startedAt = ProcessInfo.processInfo.systemUptime
                (timeoutCommand, lateCommand) = MainActor.assumeIsolated {
                    (
                        ImageUITestSupport.metrics.timeoutCommand,
                        ImageUITestSupport.metrics.lateCommand
                    )
                }
                // Target retention keeps a deliberately noncooperative old
                // source alive until the explicit late-response event arrives.
                ageTimer = Timer.scheduledTimer(
                    timeInterval: 0.05, target: self, selector: #selector(readCommands),
                    userInfo: id, repeats: true)
            } else {
                respond(status: url.path.contains("failure") ? 404 : 200)
            }
        }

        override func stopLoading() {
            lock.lock()
            defer { lock.unlock() }
            guard end == nil else { return }
            end = .cancellation
            let path = request.url?.path ?? ""
            Task { @MainActor in
                ImageUITestSupport.metrics.cancellations += 1
                if path.hasPrefix("/banner-") {
                    ImageUITestSupport.metrics.urlCancellations[path, default: 0] += 1
                    ImageUITestSupport.metrics.lateAttempts += 1
                }
            }
            if path == "/banner-pending-a" {
                removeEvents()
                respond(status: 200)
            }
        }

        @objc private func readCommands() {
            lock.lock()
            defer { lock.unlock() }
            // Bridge lifecycle and this timer run on the main run loop. This
            // closure captures no non-Sendable protocol instance.
            let commands = MainActor.assumeIsolated {
                (ImageUITestSupport.metrics.timeoutCommand, ImageUITestSupport.metrics.lateCommand)
            }
            if end == nil && !ageRecorded && ProcessInfo.processInfo.systemUptime - startedAt >= 11
            {
                ageRecorded = true
                Task { @MainActor in ImageUITestSupport.metrics.pendingPastDeadline = true }
            }
            if end == nil && commands.0 > timeoutCommand {
                end = .timeout
                removeEvents()
                Task { @MainActor in ImageUITestSupport.metrics.timeouts += 1 }
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            } else if end == .cancellation && commands.1 > lateCommand {
                removeEvents()
                Task { @MainActor in ImageUITestSupport.metrics.lateResponses += 1 }
                // Actual old callbacks enter the bridge after Nuke cancellation.
                respond(status: 200)
            }
        }

        private func removeEvents() {
            ageTimer?.invalidate()
            ageTimer = nil
        }

        private func respond(status: Int) {
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: status,
                    httpVersion: nil, headerFields: ["Content-Type": "image/png"]),
                let bytes = Data(
                    base64Encoded: url.path.hasSuffix("-b")
                        // Self-authored pink B; late pending A stays blue.
                        ? "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAHUlEQVR4nGO4aBROU8QwasGoBaMWjFowasFQsAAAFQ20HxvYnNUAAAAASUVORK5CYII="
                        : "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAHUlEQVR4nGOQS3lGU8QwasGoBaMWjFowasFQsAAAddvQHxXJaVoAAAAASUVORK5CYII="
                )
            else { return }
            if end == nil { end = status == 200 ? .success : .failure }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
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
            if mode == .bannerRefreshFailure && call == 2 { throw HomeLoadFailure.timeout }
            if mode == .bannerPending && call >= 2 {
                while true { try await Task.sleep(nanoseconds: 50_000_000) }
            }
            let base = try await FixtureHomeService().loadHome()
            if mode == .couponMany { return couponSnapshot(base) }
            if mode.rawValue.hasPrefix("banner-") {
                return bannerSnapshot(base: base, call: call)
            }
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

        private func couponSnapshot(_ base: HomeSnapshot) -> HomeSnapshot {
            let image = URL(string: "https://image-tests.invalid/success-a")
            func products(_ items: [HomeProductSummary]) -> [HomeProductSummary] {
                items.map {
                    HomeProductSummary(
                        id: $0.id, title: $0.title, subtitle: $0.subtitle, imageURL: image,
                        priceYuan: $0.priceYuan, sold: $0.sold)
                }
            }
            let extra = (4...7).map { index in
                HomeCouponSummary(
                    claimOffer: CouponClaimOffer(
                        id: Int64(860000 + index), title: "滚动测试券 \(index)",
                        description: "第\(index)张券独立说明", amountYuan: Decimal(index),
                        minimumSpendYuan: Decimal(index * 100), endTime: "2030-01-01 00:00:00"))
            }
            return HomeSnapshot(
                banners: base.banners.enumerated().map { index, banner in
                    HomeBanner(
                        id: banner.id, description: banner.description,
                        imageURL: index == 0 ? image : nil)
                },
                categories: base.categories.map {
                    HomeCategory(
                        id: $0.id, name: $0.name, parentID: $0.parentID, imageURL: image)
                },
                allCategories: base.allCategories, featured: products(base.featured),
                recommendations: products(base.recommendations), goods: products(base.goods),
                coupons: base.coupons + extra)
        }

        private func bannerSnapshot(base: HomeSnapshot, call: Int) -> HomeSnapshot {
            var order = [0, 1, 2]
            if mode == .bannerSingle { order = [1] }
            if mode == .bannerReconcile {
                switch call {
                case 2: order = [2, 1, 0]
                case 3: order = [2, 0]
                case 4: order = []
                case 5...: order = [0]
                default: break
                }
            }
            let banners = order.map { index in
                let path: String?
                switch (mode, index) {
                case (.bannerMultiple, 1): path = "/banner-failure-b"
                case (.bannerMultiple, 2), (.bannerPending, 2): path = nil
                case (.bannerPending, 0): path = "/banner-pending-a"
                case (.bannerSingle, _):
                    path = call == 1 ? "/banner-success-b" : "/banner-success-a"
                default: path = "/banner-success-\(["a", "b", "c"][index])"
                }
                return HomeBanner(
                    id: 910_001 + Int64(index), description: "受控轮播\(["A", "B", "C"][index])",
                    imageURL: path.flatMap { URL(string: "https://image-tests.invalid\($0)") })
            }
            return HomeSnapshot(
                banners: banners, categories: base.categories, allCategories: base.allCategories,
                featured: base.featured, recommendations: base.recommendations,
                goods: base.goods, coupons: base.coupons)
        }
    }
#endif
