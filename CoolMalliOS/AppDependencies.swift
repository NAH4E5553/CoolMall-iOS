import Foundation
import MallCore
import MallData
import MallImages

/// App lifetime owns the single guest fixture store and the one-time home
/// read service assembly (H0): a single HTTPHomeService in normal Debug and
/// Release; DEBUG test launch arguments may substitute a deterministic
/// service. No environment switch, no fake fallback in Release.
@MainActor
struct AppDependencies {
    let products = FixtureProductService()
    let cart = FakeCartStore(scope: CartScope(environment: "fixture", accountID: nil))
    let home: any HomeLoading
    let imagePipeline: MallImagePipeline?

    #if DEBUG
        let homeTesting = HomeUITestSupport()
        private(set) var imageTesting: ImageUITestSupport?
    #endif

    /// App-declared home source marker (H0): identifies the assembled service;
    /// it does not by itself prove a successful request.
    var homeSourceDescription: String {
        #if DEBUG
            homeTesting.sourceDescription
        #else
            "真实接口"
        #endif
    }

    /// Fixed home fixtures never use production CDN transport.
    var homeImagePipeline: MallImagePipeline? {
        #if DEBUG
            if homeTesting.fixtureMode != nil { return imageTesting?.pipeline }
        #endif
        return imagePipeline
    }

    var showsHomeReadVerification: Bool {
        #if DEBUG
            homeTesting.fixtureMode != nil
        #else
            false
        #endif
    }

    private static let homeBaseURL: URL = {
        // Fixed production base (Android convention plugin, A-PAGE-01).
        guard let url = URL(string: "https://mall.dusksnow.top/app/") else {
            fatalError("fixed home base URL must be valid")
        }
        return url
    }()

    private static func makeProductionImages() -> MallImagePipeline? {
        let images = MallImageConfiguration(cacheNamespace: "mall-production-public-v1")
        do { return try MallImagePipeline(configuration: images) } catch {
            print("图片磁盘缓存不可用，尝试仅内存缓存")
            do {
                return try MallImagePipeline(
                    configuration: .init(diskLimitBytes: 0, cacheNamespace: images.cacheNamespace))
            } catch {
                print("图片管线不可用，保留占位")
                return nil
            }
        }
    }

    init() {
        #if DEBUG
            let controlled = ImageUITestSupport(mode: homeTesting.fixtureMode)
            imageTesting = controlled
            imagePipeline = controlled != nil ? controlled?.pipeline : Self.makeProductionImages()
        #else
            imagePipeline = Self.makeProductionImages()
        #endif
        let environment = APIEnvironment(baseURL: Self.homeBaseURL)
        #if DEBUG
            if let testService = homeTesting.service {
                home = testService
            } else {
                home = HTTPHomeService(environment: environment)
            }
        #else
            home = HTTPHomeService(environment: environment)
        #endif
    }
}
