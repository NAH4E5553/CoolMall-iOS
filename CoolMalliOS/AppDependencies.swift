import MallCore
import MallData

/// App lifetime owns the single guest fixture store. No credentials or remote services in F0.
struct AppDependencies {
    let products = FixtureProductService()
    let cart = FakeCartStore(scope: CartScope(environment: "fixture", accountID: nil))
}
