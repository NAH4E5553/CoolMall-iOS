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
    let shoppingCart: any ShoppingCart
    let cartVerifier: any CartProductChecking
    let home: any HomeLoading
    let productReviews: any ProductReviewsLoading
    let productDetails: any ProductDetailLoading
    let category: any CategoryLoading
    let imagePipeline: MallImagePipeline?

    #if DEBUG
        let homeTesting = HomeUITestSupport()
        let productDetailTesting = ProductDetailUITestService.make(
            arguments: ProcessInfo.processInfo.arguments)
        let categoryTesting: CategoryUITestSupport
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

    var detailImagePipeline: MallImagePipeline? {
        #if DEBUG
            if productDetailTesting != nil { return nil }
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

    /// Category fixtures stay offline-deterministic: only an explicit home
    /// image fixture supplies a controlled pipeline; a category fixture alone
    /// therefore renders the documented image placeholders. Normal Debug and
    /// Release use the same production image pipeline as home.
    var categoryImagePipeline: MallImagePipeline? {
        #if DEBUG
            if categoryTesting.mode != nil { return imageTesting?.pipeline }
        #endif
        return imagePipeline
    }

    var showsCategoryReadVerification: Bool {
        #if DEBUG
            categoryTesting.mode != nil
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
            let categorySupport = CategoryUITestSupport()
            categoryTesting = categorySupport
            let controlled = ImageUITestSupport(mode: homeTesting.fixtureMode)
            imageTesting = controlled
            imagePipeline = controlled != nil ? controlled?.pipeline : Self.makeProductionImages()
        #else
            imagePipeline = Self.makeProductionImages()
        #endif
        let environment = APIEnvironment(baseURL: Self.homeBaseURL)
        #if DEBUG
            productReviews =
                ProductReviewsUITestService.make(arguments: ProcessInfo.processInfo.arguments)
                ?? HTTPProductReviewsService(environment: environment)
            productDetails =
                productDetailTesting ?? HTTPProductDetailService(environment: environment)
        #else
            productReviews = HTTPProductReviewsService(environment: environment)
            productDetails = HTTPProductDetailService(environment: environment)
        #endif
        cartVerifier = CartProductVerifier(loader: productDetails)
        let support = URL.applicationSupportDirectory.appending(
            path: "ShoppingCart", directoryHint: .isDirectory)
        #if DEBUG
            if let fixture = CartUITestSupport.make(loader: productDetails, directory: support) {
                shoppingCart = fixture
            } else {
                shoppingCart = LocalShoppingCart(
                    scope: CartScope(environment: Self.homeBaseURL.absoluteString, accountID: nil),
                    url: support.appending(path: "cart-v1.store"))
            }
        #else
            shoppingCart = LocalShoppingCart(
                scope: CartScope(environment: Self.homeBaseURL.absoluteString, accountID: nil),
                url: support.appending(path: "cart-v1.store"))
        #endif
        #if DEBUG
            if let testService = homeTesting.service {
                home = testService
            } else {
                home = HTTPHomeService(environment: environment)
            }
            if categorySupport.configError {
                category = ConfigErrorCategoryService()
            } else if let testService = categorySupport.service {
                category = testService
            } else {
                category = HTTPCategoryService(environment: environment)
            }
        #else
            home = HTTPHomeService(environment: environment)
            category = HTTPCategoryService(environment: environment)
        #endif
    }
}
