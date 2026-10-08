import Observation

/// Each RootView/Scene owns its router. Features only send navigation intents.
@MainActor @Observable
final class SceneRouter {
    enum Tab: Hashable { case home; case category; case cart; case me }
    enum Route: Hashable { case cart }
    var selectedTab: Tab = .home
    var homePath: [Route] = []
    func openCart() { homePath.append(.cart) }
}
