import Foundation
import Observation
import MallCore
import MallData
import MallImages

/// App lifetime owns the single guest fixture store and the one-time home
/// read service assembly (H0): a single HTTPHomeService in normal Debug and
/// Release; DEBUG test launch arguments may substitute a deterministic
/// service. No environment switch, no fake fallback in Release.
@MainActor @Observable
final class AppDependencies {
    let products = FixtureProductService()
    let cart = FakeCartStore(scope: CartScope(environment: "fixture", accountID: nil))
    private(set) var shoppingCart: any ShoppingCart
    let accountSession: any AccountSession
    let loginChallenges: any LoginChallenges
    let codeNotifier: any VerificationCodeDelivering
    private(set) var accountState: AccountState
    private let cartStorageURL: URL
    private(set) var footprints: any FootprintStoring
    private let footprintStorageURL: URL
    private var footprintStores: [FootprintScope: any FootprintStoring] = [:]
    private var accountCarts: [CartScope: any ShoppingCart] = [:]
    let cartVerifier: any CartProductChecking
    let home: any HomeLoading
    let productReviews: any ProductReviewsLoading
    let productDetails: any ProductDetailLoading
    let category: any CategoryLoading
    let addresses: any AddressLoading & AddressWriting
    let addressRegions: any AddressRegionsLoading
    let userCoupons: any UserCouponsLoading
    let couponProducts: any CouponProductsLoading
    let couponReceiver: any CouponReceiving
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
            if let index = ProcessInfo.processInfo.arguments.firstIndex(
                of: "--ui-account-keychain"),
                ProcessInfo.processInfo.arguments.indices.contains(index + 1),
                let namespace = UUID(uuidString: ProcessInfo.processInfo.arguments[index + 1]),
                let url = URL(
                    string: "https://" + namespace.uuidString.lowercased()
                        + ".account-keychain.invalid/app/")
            {
                let session = SessionCoordinator(environment: APIEnvironment(baseURL: url))
                accountSession = session; loginChallenges = session
                codeNotifier = AccountUITestSupport(scenario: "success")
            } else if let fixture = AccountUITestSupport.make(
                arguments: ProcessInfo.processInfo.arguments)
            {
                accountSession = fixture; loginChallenges = fixture
                codeNotifier =
                    ProcessInfo.processInfo.arguments.contains("--ui-account-system-notification")
                    ? LocalVerificationCodeNotifier() : fixture
            } else {
                let session = SessionCoordinator(environment: environment)
                accountSession = session; loginChallenges = session;
                codeNotifier = LocalVerificationCodeNotifier()
            }
        #else
            let session = SessionCoordinator(environment: environment)
            accountSession = session; loginChallenges = session;
            codeNotifier = LocalVerificationCodeNotifier()
        #endif
        #if DEBUG
            if let fixture = CouponUITestSupport.make(arguments: ProcessInfo.processInfo.arguments)
            {
                userCoupons = fixture; couponProducts = fixture; couponReceiver = fixture
            } else if let session = accountSession as? SessionCoordinator {
                userCoupons = HTTPUserCouponService(environment: environment, session: session)
                couponProducts = HTTPCouponProductsService(environment: environment)
                couponReceiver = HTTPCouponReceiver(environment: environment, session: session)
            } else {
                userCoupons = UnavailableCouponReads(); couponProducts = UnavailableCouponReads();
                couponReceiver = UnavailableCouponReads()
            }
        #else
            userCoupons = HTTPUserCouponService(environment: environment, session: session)
            couponProducts = HTTPCouponProductsService(environment: environment)
            couponReceiver = HTTPCouponReceiver(environment: environment, session: session)
        #endif
        addressRegions = BundledAddressRegions()
        #if DEBUG
            if let fixture = AddressUITestSupport.make(arguments: ProcessInfo.processInfo.arguments)
            {
                addresses = fixture
            } else if let session = accountSession as? SessionCoordinator {
                addresses = HTTPAddressService(environment: environment, session: session)
            } else {
                addresses = UnavailableAddressService()
            }
        #else
            addresses = HTTPAddressService(environment: environment, session: session)
        #endif
        let initialAccountState = accountSession.initialState
        accountState = initialAccountState
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
        var storageURL = support.appending(path: "cart-v1.store")
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--ui-cart-store"),
                arguments.indices.contains(index + 1),
                let token = UUID(uuidString: arguments[index + 1])
            {
                storageURL = support.appending(path: "test-\(token.uuidString).store")
            }
        #endif
        cartStorageURL = storageURL
        #if DEBUG
            if let fixture = CartUITestSupport.make(loader: productDetails, directory: support) {
                shoppingCart = fixture
            } else {
                shoppingCart = LocalShoppingCart(
                    scope: CartScope(
                        environment: Self.homeBaseURL.absoluteString,
                        accountID: initialAccountState.profile.map { String($0.id) }),
                    url: support.appending(path: "cart-v1.store"))
            }
        #else
            shoppingCart = LocalShoppingCart(
                scope: CartScope(
                    environment: Self.homeBaseURL.absoluteString,
                    accountID: initialAccountState.profile.map { String($0.id) }),
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
        let historyURL = URL.applicationSupportDirectory.appending(
            path: "Footprints", directoryHint: .isDirectory
        ).appending(path: storageURL.lastPathComponent)
        footprintStorageURL = historyURL
        let historyScope = FootprintScope(
            environment: Self.homeBaseURL.absoluteString,
            accountID: initialAccountState.profile.map { String($0.id) })
        footprints = PersistentFootprintStore(scope: historyScope, url: historyURL)
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-footprints-seed")
                || ProcessInfo.processInfo.arguments.contains("--ui-footprints-failure")
            {
                let args = ProcessInfo.processInfo.arguments
                let failureIndex = args.firstIndex(of: "--ui-footprints-failure")
                let failure = failureIndex.flatMap {
                    args.indices.contains($0 + 1) ? args[$0 + 1] : nil
                }
                footprints = FootprintUITestSupport(
                    store: footprints, seed: args.contains("--ui-footprints-seed"), failure: failure
                )
            }
        #endif
        footprintStores[historyScope] = footprints
        accountCarts[shoppingCart.scope] = shoppingCart
    }
    /// Scope identity is selected only from a committed session profile. Each
    /// partition reuses its own store; login never copies guest rows.
    func applyAccount(_ state: AccountState) {
        let scope = CartScope(
            environment: shoppingCart.scope.environment,
            accountID: state.profile.map { String($0.id) })
        if scope != shoppingCart.scope {
            let store = accountCarts[scope] ?? LocalShoppingCart(scope: scope, url: cartStorageURL)
            accountCarts[scope] = store; shoppingCart = store
        }
        let historyScope = FootprintScope(
            environment: Self.homeBaseURL.absoluteString, accountID: scope.accountID)
        if historyScope != footprints.scope {
            let store =
                footprintStores[historyScope]
                ?? PersistentFootprintStore(scope: historyScope, url: footprintStorageURL)
            footprintStores[historyScope] = store; footprints = store
        }
        accountState = state
    }

}

#if DEBUG
    private struct UnavailableCouponReads: UserCouponsLoading, CouponProductsLoading,
        CouponReceiving
    {
        func receiveCoupon(accountID: Int64, couponID: Int64) async throws -> String? {
            throw CouponClaimFailure.invalidConfiguration
        }
        func loadCoupons(accountID: Int64, page: Int, pageSize: Int) async throws -> NumberedPage<
            UserCoupon
        > { throw PageReadFailure.invalidConfiguration }
        func loadProducts(minimumPriceYuan: Decimal?, page: Int, pageSize: Int) async throws
            -> NumberedPage<CouponProductSummary>
        { throw PageReadFailure.invalidConfiguration }
    }
#endif

#if DEBUG
    private struct UnavailableAddressService: AddressLoading, AddressWriting {
        func loadAddresses(accountID: Int64, page: Int, pageSize: Int) async throws -> NumberedPage<
            ShippingAddress
        > { throw PageReadFailure.invalidConfiguration }
        func loadAddress(accountID: Int64, id: Int64) async throws -> ShippingAddress {
            throw PageReadFailure.invalidConfiguration
        }
        func saveAddress(accountID: Int64, id: Int64?, input: ShippingAddressInput) async throws {
            throw AddressWriteFailure.invalidInput
        }
        func deleteAddress(accountID: Int64, id: Int64) async throws {
            throw AddressWriteFailure.invalidInput
        }
    }
#endif
