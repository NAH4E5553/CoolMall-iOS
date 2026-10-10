import Observation

/// Each RootView/Scene owns its router. Features only send navigation intents.
/// NAV-02: every tab holds its own path; no tab's operation writes another
/// tab's stack (PRD-013/NAV-R02).
/// NAV-03: typed product-detail intents push onto the source tab's stack so
/// back naturally restores the same detail, goodsId and source tab
/// (NAV-R03/PRD-017).
@MainActor @Observable
final class SceneRouter {
    enum Tab: Hashable { case home; case category; case cart; case me }
    enum Route: Hashable {
        case cart
        /// NAV-03 typed route. The placeholder destination only displays the
        /// goodsId; it loads nothing and writes nothing.
        case productDetail(goodsID: Int64)
        /// Engineering fixture only: keeps per-tab path behavior observable until
        /// real typed routes replace it. Not a business destination.
        case fixturePathProbe(label: String)
    }
    var selectedTab: Tab = .home
    var homePath: [Route] = []
    var categoryPath: [Route] = []
    var cartPath: [Route] = []
    var mePath: [Route] = []
    func openCart() { homePath.append(.cart) }
    /// Appends a route onto the owning tab's stack, so a destination pushed
    /// from that stack (e.g. the independent cart from a detail page) returns
    /// to the same stack and never swaps the source tab.
    func append(_ route: Route, on tab: Tab) {
        switch tab {
        case .home: homePath.append(route)
        case .category: categoryPath.append(route)
        case .cart: cartPath.append(route)
        case .me: mePath.append(route)
        }
    }

    /// HOME-02-R1 (DEC-010/PRD-019): internal home re-tap event counter.
    private var homeReTapCount: UInt64 = 0

    /// Read-only re-tap event for the home entry. Monotonic per Scene; the
    /// entry consumes it as a refresh request, never as a raw task key.
    var homeReTapEvent: UInt64 { homeReTapCount }

    /// App-side entry for TabView selection writes (RootView's binding). A
    /// write that keeps the already-selected home tab selected at its root is
    /// a user re-tap: bump the event counter. Writes that change the tab only
    /// set `selectedTab`; programmatic switches write `selectedTab` directly
    /// and can never fabricate the event.
    func selectFromTabBar(_ tab: Tab) {
        if tab == selectedTab, tab == .home, homePath.isEmpty {
            homeReTapCount &+= 1
        }
        selectedTab = tab
    }
}
