#if DEBUG
    import Foundation
    import MallCore
    import MallData
    import SwiftUI

    /// DEBUG-only UI-test input synthesis (H0 test-assembly contract). Parses the
    /// two mutually exclusive launch modes and builds the deterministic services;
    /// conflicting or illegal arguments surface as an explicit test-configuration
    /// error instead of silently picking a mode. No production HTTP request or
    /// DTO mapping happens here, and Release builds compile this file away.
    struct HomeUITestSupport {
        enum HomeRoot {
            case home
            case catalogFixture
            case testConfigError
        }

        enum FixtureMode: String {
            case bannerSingle = "banner-single"
            case bannerMultiple = "banner-multiple"
            case bannerReconcile = "banner-reconcile"
            case bannerRefreshFailure = "banner-refresh-failure"
            case bannerPending = "banner-pending"
            case imageSuccess = "image-success"
            case imageFailure = "image-failure"
            case imagePending = "image-pending"
            case pageControlled = "page-controlled"
            case valid
            case empty
            case retry
            /// R-HOME-01-03 evidence mode: six display arrays empty while the
            /// auxiliary full-category list is non-empty — the empty UI must
            /// still expose the observable counts.
            case emptyCategory = "empty-category"
            /// HOME-02 approved evidence mode (9.7.5): banners 0 / coupons 1 /
            /// categories 0 / featured 1 / recommendations 2 / goods 1 /
            /// allCategories 3 — synthetic legal entries only (positive
            /// unique ids, nil image URLs, clearly-test titles; the two
            /// recommendations cover short and long titles).
            case layoutMixed = "layout-mixed"
            /// HOME-02-R1 (9.8.6): call 1 returns the valid base (A); call 2
            /// returns B (goods = A+1); call 3+ returns C (goods = A+2) —
            /// appended goods are synthetic legal entries.
            case retapSequence = "retap-sequence"
            /// HOME-02-R1 (9.8.6): call 1 = A; call 2 throws a known
            /// HomeLoadFailure; call 3+ = B (goods = A+1).
            case retapFailure = "retap-failure"
            /// HOME-02-R1 (9.8.6): call 1 = A; every later call suspends
            /// (cancellation-responsive sleeps) until cancelled.
            case retapPending = "retap-pending"
        }

        let root: HomeRoot
        let fixtureMode: FixtureMode?
        let service: (any HomeLoading)?

        var sourceDescription: String {
            switch root {
            case .home:
                if let fixtureMode {
                    return "工程夹具（\(fixtureMode.rawValue)）"
                }
                return "真实接口"
            case .catalogFixture:
                return "工程夹具（导航）"
            case .testConfigError:
                return "测试配置错误"
            }
        }

        @MainActor init(arguments: [String] = ProcessInfo.processInfo.arguments) {
            let hasNavFixture = arguments.contains("--uitest-nav-fixture")
            let homeFlagIndex = arguments.firstIndex(of: "--ui-home-fixture")
            var homeValue: String?
            // R-HOME-01-04: a present flag with a missing or flag-like value
            // must fail closed as a test-configuration error — it may never
            // fall through to the real HTTP service.
            var homeFlagWithoutValue = false
            if let homeFlagIndex {
                let next = homeFlagIndex + 1
                if next < arguments.count, !arguments[next].hasPrefix("-") {
                    homeValue = arguments[next]
                } else {
                    homeFlagWithoutValue = true
                }
            }

            if hasNavFixture && homeFlagIndex != nil {
                root = .testConfigError
                fixtureMode = nil
                service = nil
                return
            }
            if hasNavFixture {
                root = .catalogFixture
                fixtureMode = nil
                service = nil
                return
            }
            if homeFlagWithoutValue {
                root = .testConfigError
                fixtureMode = nil
                service = nil
                return
            }
            if let homeValue {
                guard let mode = FixtureMode(rawValue: homeValue) else {
                    root = .testConfigError
                    fixtureMode = nil
                    service = nil
                    return
                }
                root = .home
                fixtureMode = mode
                switch mode {
                case .imageSuccess, .imageFailure, .imagePending,
                    .bannerSingle, .bannerMultiple, .bannerReconcile,
                    .bannerRefreshFailure, .bannerPending:
                    service = ImageHomeService(mode: mode)
                case .pageControlled: service = PageControlledHomeService()
                case .valid: service = FixtureHomeService()
                case .empty: service = EmptySnapshotService()
                case .retry: service = RetrySequenceService()
                case .emptyCategory: service = OnlyCategoryAllSnapshotService()
                case .layoutMixed: service = LayoutMixedSnapshotService()
                case .retapSequence: service = RetapSequenceService()
                case .retapFailure: service = RetapFailureService()
                case .retapPending: service = RetapPendingService()
                }
                return
            }
            root = .home
            fixtureMode = nil
            service = nil
        }
    }

    /// Deterministic valid-empty snapshot (DEBUG test input only).
    private struct EmptySnapshotService: HomeLoading {
        func loadHome() async throws -> HomeSnapshot {
            HomeSnapshot(
                banners: [], categories: [], allCategories: [], featured: [],
                recommendations: [], goods: [], coupons: []
            )
        }
    }

    /// Deterministic only-categoryAll snapshot (DEBUG test input only): the
    /// six display arrays are empty while the auxiliary category list is not.
    private struct OnlyCategoryAllSnapshotService: HomeLoading {
        func loadHome() async throws -> HomeSnapshot {
            HomeSnapshot(
                banners: [], categories: [],
                allCategories: [
                    HomeCategory(id: 800_001, name: "手机", parentID: nil, imageURL: nil),
                    HomeCategory(id: 800_002, name: "电脑", parentID: 800_001, imageURL: nil),
                    HomeCategory(id: 800_003, name: "家电", parentID: nil, imageURL: nil),
                ],
                featured: [], recommendations: [], goods: [], coupons: []
            )
        }
    }

    /// HOME-02 approved deterministic input (DEBUG only, 9.7.5): the six
    /// display arrays count 0/1/0/1/2/1 with an auxiliary 3. Synthetic legal
    /// entries only; recommendations carry one short and one long title.
    private struct LayoutMixedSnapshotService: HomeLoading {
        func loadHome() async throws -> HomeSnapshot {
            HomeSnapshot(
                banners: [],
                categories: [],
                allCategories: [
                    HomeCategory(id: 810_001, name: "合成分类甲", parentID: nil, imageURL: nil),
                    HomeCategory(id: 810_002, name: "合成分类乙", parentID: 810_001, imageURL: nil),
                    HomeCategory(
                        id: 810_003, name: "合成分类丙长标题（测试输入，用于特大字体换行）",
                        parentID: nil, imageURL: nil),
                ],
                featured: [
                    HomeProductSummary(
                        id: 830_101, title: "合成精选商品（测试输入）", subtitle: nil,
                        imageURL: nil, priceYuan: Decimal(1))
                ],
                recommendations: [
                    HomeProductSummary(
                        id: 830_102, title: "合成推荐短", subtitle: nil,
                        imageURL: nil, priceYuan: Decimal(2)),
                    HomeProductSummary(
                        id: 830_103,
                        title: "合成推荐长标题——测试输入，验证长文字换行与左对齐",
                        subtitle: nil, imageURL: nil, priceYuan: Decimal(3)),
                ],
                goods: [
                    HomeProductSummary(
                        id: 830_104, title: "合成全部商品（测试输入）", subtitle: nil,
                        imageURL: nil, priceYuan: Decimal(4))
                ],
                coupons: [HomeCouponSummary(id: 860_101, title: "合成优惠券（测试输入）")]
            )
        }
    }

    /// HOME-02-R1 deterministic sequence (DEBUG only): A (valid base),
    /// B (goods = A+1), then C (goods = A+2). Appended goods are synthetic
    /// legal entries with ids outside the base fixture's ranges.
    private actor RetapSequenceService: HomeLoading {
        private var calls = 0
        private let base = FixtureHomeService()

        func loadHome() async throws -> HomeSnapshot {
            calls += 1
            let snapshot = try await base.loadHome()
            let additions = min(calls - 1, 2)
            let extra = (0..<additions).map { index in
                HomeProductSummary(
                    id: 999_001 + Int64(index),
                    title: "合成重按商品\(index + 1)（测试输入）",
                    subtitle: nil, imageURL: nil, priceYuan: Decimal(1))
            }
            return HomeSnapshot(
                banners: snapshot.banners,
                categories: snapshot.categories,
                allCategories: snapshot.allCategories,
                featured: snapshot.featured,
                recommendations: snapshot.recommendations,
                goods: snapshot.goods + extra,
                coupons: snapshot.coupons)
        }
    }

    /// HOME-02-R1 deterministic failure path (DEBUG only): A, then a known
    /// HomeLoadFailure, then B (goods = A+1).
    private actor RetapFailureService: HomeLoading {
        private var calls = 0
        private let base = FixtureHomeService()

        func loadHome() async throws -> HomeSnapshot {
            calls += 1
            if calls == 2 { throw HomeLoadFailure.timeout }
            let snapshot = try await base.loadHome()
            if calls < 3 { return snapshot }
            let extra = HomeProductSummary(
                id: 999_011, title: "合成重按成功商品（测试输入）",
                subtitle: nil, imageURL: nil, priceYuan: Decimal(1))
            return HomeSnapshot(
                banners: snapshot.banners,
                categories: snapshot.categories,
                allCategories: snapshot.allCategories,
                featured: snapshot.featured,
                recommendations: snapshot.recommendations,
                goods: snapshot.goods + [extra],
                coupons: snapshot.coupons)
        }
    }

    /// HOME-02-R1 controlled suspension (DEBUG only): the first read returns
    /// the valid base; every later read suspends on cancellation-responsive
    /// sleeps until the surrounding task is cancelled.
    private actor RetapPendingService: HomeLoading {
        private var calls = 0
        private let base = FixtureHomeService()

        func loadHome() async throws -> HomeSnapshot {
            calls += 1
            if calls >= 2 {
                while true {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            return try await base.loadHome()
        }
    }

    /// Deterministic retry sequence (DEBUG test input only): the first read fails
    /// with a recoverable error, the user's retry succeeds with a small synthetic
    /// snapshot — no HTTP, no DTO mapping.
    private actor RetrySequenceService: HomeLoading {
        private var calls = 0

        func loadHome() async throws -> HomeSnapshot {
            calls += 1
            if calls == 1 { throw HomeLoadFailure.networkUnavailable }
            return HomeSnapshot(
                banners: [HomeBanner(id: 900_001, description: "重试成功夹具", imageURL: nil)],
                categories: [],
                allCategories: [],
                featured: [
                    HomeProductSummary(
                        id: 830_001,
                        title: "重试成功商品",
                        subtitle: nil,
                        imageURL: nil,
                        priceYuan: Decimal(3999)
                    )
                ],
                recommendations: [],
                goods: [],
                coupons: [HomeCouponSummary(id: 860_001, title: "重试成功券")]
            )
        }
    }

    /// Test events release the real injected HomeLoading continuation; they
    /// never mutate the page or fabricate request/cancellation counters.
    @MainActor
    final class PageControlledHomeService: HomeLoading {
        static let events = PageHomeEvents()
        private var call = 0
        init() { Self.events.reset() }
        func loadHome() async throws -> HomeSnapshot {
            call += 1
            Self.events.calls = call
            if call == 1 { return try await FixtureHomeService().loadHome() }
            // HOME-RETAP-DEBOUNCE: pending requests are stored PER REQUEST
            // identity; a NEW arrival neither cancels nor answers an older
            // one — the cancellation counter moves ONLY in the request's own
            // cancellation handler (R-LATEST-02).
            let requestID = UUID()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    Self.events.register(requestID: requestID, continuation: continuation)
                }
            } onCancel: {
                Task { @MainActor in
                    Self.events.cancel(requestID: requestID)
                }
            }
        }
    }

    @MainActor
    final class PageHomeEvents: ObservableObject {
        @Published var calls = 0
        @Published var cancellations = 0
        /// Pendings keyed by request identity; `latestID` is the CURRENT
        /// intent the release buttons answer. Superseded-but-uncancelled
        /// requests stay pending (their tasks still await) until their own
        /// cancellation handler or a release removes them.
        private var pendings: [UUID: CheckedContinuation<HomeSnapshot, Error>] = [:]
        private(set) var latestID: UUID?
        func register(requestID: UUID, continuation: CheckedContinuation<HomeSnapshot, Error>) {
            pendings[requestID] = continuation
            latestID = requestID
        }
        /// Real cancellation evidence: ONLY the request's own cancellation
        /// handler may call this; a new arrival never touches older ones.
        func cancel(requestID: UUID) {
            guard let continuation = pendings.removeValue(forKey: requestID) else { return }
            cancellations += 1
            if latestID == requestID { latestID = nil }
            continuation.resume(throwing: CancellationError())
        }
        func reset() {
            for continuation in pendings.values {
                continuation.resume(throwing: CancellationError())
            }
            pendings = [:]
            latestID = nil
            calls = 0
            cancellations = 0
        }
        /// Answers the LATEST still-pending request (the current intent).
        func release(_ result: Result<HomeSnapshot, Error>) {
            guard let id = latestID, let continuation = pendings.removeValue(forKey: id) else {
                return
            }
            latestID = nil
            continuation.resume(with: result)
        }
        func succeed() async {
            guard let requestID = latestID else { return }
            do {
                let base = try await FixtureHomeService().loadHome()
                guard latestID == requestID else { return }
                let extra = HomeProductSummary(
                    id: 990_001, title: "刷新商品", subtitle: nil, imageURL: nil, priceYuan: Decimal(88)
                )
                release(
                    .success(
                        HomeSnapshot(
                            banners: base.banners, categories: base.categories,
                            allCategories: base.allCategories, featured: base.featured,
                            recommendations: base.recommendations, goods: base.goods + [extra],
                            coupons: base.coupons)))
            } catch {
                if latestID == requestID { release(.failure(error)) }
            }
        }
    }

    struct PageHomeTestControlsView: View {
        @ObservedObject private var events = PageControlledHomeService.events
        var body: some View {
            HStack {
                Text("读取：\(events.calls)；取消：\(events.cancellations)")
                    .accessibilityIdentifier("home.page.requests")
                Button("返回成功") { Task { await events.succeed() } }
                    .accessibilityIdentifier("home.page.success")
                Button("返回失败") { events.release(.failure(HomeLoadFailure.timeout)) }
                    .accessibilityIdentifier("home.page.failure")
            }.font(.caption2)
        }
    }
#endif
