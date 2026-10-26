import Foundation
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
        case login
        case profile
        case footprints
        case addresses
        case addressEditor(id: Int64?)
        case coupons
        case couponProducts(minimumPriceYuan: Decimal?)
        /// Typed route into the real read-only detail entry. The explicit DEBUG
        /// catalog fixture retains its original navigation-only probe.
        case productDetail(goodsID: Int64)
        case productReviews(goodsID: Int64)
        /// Engineering fixture only: keeps per-tab path behavior observable until
        /// real typed routes replace it. Not a business destination.
        case fixturePathProbe(label: String)
    }
    var selectedTab: Tab = .home {
        didSet {
            #if DEBUG
                if oldValue != selectedTab { recordBannerRouteInput() }
            #endif
        }
    }
    var homePath: [Route] = [] {
        didSet {
            #if DEBUG
                if oldValue != homePath { recordBannerRouteInput() }
            #endif
        }
    }
    var categoryPath: [Route] = []
    var cartPath: [Route] = []
    var mePath: [Route] = []
    #if DEBUG
        @ObservationIgnored private var bannerLifecycle = BannerAppLifecycle()

        /// Observe the actual Scene phase received by the App. The logger has
        /// no navigation/timer write authority and does not infer OS timing.
        func recordBannerSceneInput(isActive: Bool) {
            bannerLifecycle.sceneInput(
                homeActive: selectedTab == .home && homePath.isEmpty, sceneActive: isActive)
        }

        private func recordBannerRouteInput() {
            // didSet runs after the real router assignment, before yielding.
            bannerLifecycle.routeInput(homeActive: selectedTab == .home && homePath.isEmpty)
        }
    #endif

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

#if DEBUG
    /// Opt-in evidence owned by the existing Scene router. It records real
    /// assignments only; no timer, route, or feature state reads this ledger.
    @MainActor
    final class BannerAppLifecycle {
        private let runID: String?
        private let instanceID = UUID().uuidString
        private var sequence: UInt64 = 0
        private var inputRevision: UInt64 = 0
        private var homeActive: Bool?
        private var sceneActive: Bool?

        init() {
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--ui-banner-audit-run-id"),
                arguments.indices.contains(flag + 1), !arguments[flag + 1].isEmpty
            {
                runID = arguments[flag + 1]
            } else {
                runID = nil
            }
        }

        func sceneInput(homeActive: Bool, sceneActive: Bool) {
            guard runID != nil else { return }
            if self.homeActive == nil {
                self.homeActive = homeActive
                self.sceneActive = sceneActive
                record("initial", oldHome: homeActive, oldScene: sceneActive)
            } else if self.sceneActive != sceneActive {
                let oldHome = self.homeActive ?? homeActive
                let oldScene = self.sceneActive ?? sceneActive
                self.homeActive = homeActive
                self.sceneActive = sceneActive
                inputRevision &+= 1
                record("sceneInput", oldHome: oldHome, oldScene: oldScene)
            }
        }

        func routeInput(homeActive: Bool) {
            // Initial is captured after seeded routing and the real Scene
            // environment arrive; unused pre-render routers emit no events.
            guard let oldHome = self.homeActive, let sceneActive,
                oldHome != homeActive
            else { return }
            self.homeActive = homeActive
            inputRevision &+= 1
            record("routeInput", oldHome: oldHome, oldScene: sceneActive)
        }

        private func record(_ event: String, oldHome: Bool, oldScene: Bool) {
            guard let runID, let homeActive, let sceneActive else { return }
            sequence &+= 1
            let value: [String: Any] = [
                "schemaVersion": 1, "runID": runID, "origin": "app",
                "processID": ProcessInfo.processInfo.processIdentifier,
                "instanceID": instanceID, "eventSequence": sequence,
                "monotonicTime": ProcessInfo.processInfo.systemUptime,
                "inputRevision": inputRevision, "event": event,
                "homeActive": homeActive, "sceneActive": sceneActive,
                "oldHomeActive": oldHome, "oldSceneActive": oldScene,
            ]
            guard
                let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys),
                let json = String(data: data, encoding: .utf8)
            else {
                NSLog("BANNERAUDIT_ERROR encoding-failed runID=%@", runID)
                return
            }
            NSLog("BANNERAUDIT %@", json)
        }
    }
#endif
