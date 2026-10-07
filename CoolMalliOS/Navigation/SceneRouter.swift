import Observation

/// Each RootView/Scene owns its router. Features only send navigation intents.
@MainActor @Observable
final class SceneRouter {
    enum Tab: Hashable { case catalog; case cart }
    enum Route: Hashable { case cart }
    var selectedTab: Tab = .catalog
    var catalogPath: [Route] = []
    func openCart() { catalogPath.append(.cart) }
}
