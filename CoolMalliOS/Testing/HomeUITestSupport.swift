#if DEBUG
    import Foundation
    import MallCore
    import MallData

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
            case valid
            case empty
            case retry
            /// R-HOME-01-03 evidence mode: six display arrays empty while the
            /// auxiliary full-category list is non-empty — the empty UI must
            /// still expose the observable counts.
            case emptyCategory = "empty-category"
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

        init(arguments: [String] = ProcessInfo.processInfo.arguments) {
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
                case .valid: service = FixtureHomeService()
                case .empty: service = EmptySnapshotService()
                case .retry: service = RetrySequenceService()
                case .emptyCategory: service = OnlyCategoryAllSnapshotService()
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
#endif
