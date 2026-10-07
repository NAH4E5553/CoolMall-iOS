import CartFeature
import CatalogFeature
import SwiftUI

@MainActor
struct RootView: View {
    let dependencies: AppDependencies
    @State private var router = SceneRouter()
    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.catalogPath) {
                CatalogEntryView(products: dependencies.products, openCart: router.openCart)
                    .navigationDestination(for: SceneRouter.Route.self) { route in
                        switch route {
                        case .cart: CartEntryView(cart: dependencies.cart)
                        }
                    }
            }.tabItem { Label("商品", systemImage: "square.grid.2x2") }.tag(SceneRouter.Tab.catalog)
            NavigationStack { CartEntryView(cart: dependencies.cart) }
                .tabItem { Label("购物车", systemImage: "cart") }.tag(SceneRouter.Tab.cart)
        }
    }
}
