import Observation

/// Each RootView/Scene owns its router. Features only send navigation intents.
/// NAV-02: every tab holds its own path; no tab's operation writes another
/// tab's stack (PRD-013/NAV-R02).
@MainActor @Observable
final class SceneRouter {
    enum Tab: Hashable { case home; case category; case cart; case me }
    enum Route: Hashable {
        case cart
        /// Engineering fixture only: keeps per-tab path behavior observable until
        /// NAV-03 replaces it with real typed routes. Not a business destination.
        case fixturePathProbe(label: String)
    }
    var selectedTab: Tab = .home
    var homePath: [Route] = []
    var categoryPath: [Route] = []
    var cartPath: [Route] = []
    var mePath: [Route] = []
    func openCart() { homePath.append(.cart) }
}
