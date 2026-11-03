import MallCore
import Observation

/// Owned by the home page model. Home's preview has no page metadata: the first tail read starts
/// at page 1, then this coordinator becomes the sole owner of the displayed catalogue pages.
@MainActor @Observable final class HomeGoodsViewModel {
    private(set) var state: NumberedPageSnapshot<SearchProductSummary>
    private let loader: any ProductSearchLoading
    @ObservationIgnored private var pages: NumberedPageCoordinator<SearchProductSummary>
    private var active = false
    private var tailVisible = false
    private var automaticInitialAllowed = true

    init(loader: any ProductSearchLoading) {
        self.loader = loader
        let pages = Self.makePages(loader)
        self.pages = pages; state = pages.snapshot
        connect()
    }
    private static func makePages(_ loader: any ProductSearchLoading) -> NumberedPageCoordinator<
        SearchProductSummary
    > {
        NumberedPageCoordinator(pageSize: 10) { page, size in
            try await loader.search(
                SearchQuery(keyword: "", allProducts: true), page: page, pageSize: size)
        }
    }
    private func connect() {
        pages.onChange = { [weak self] snapshot in
            guard let self else { return }
            let calibrated = !self.state.hasLoaded && snapshot.hasLoaded
            self.state = snapshot
            // The first tail read calibrates the preview, which may have exactly the same height.
            // Consume that tail intent with ONE page-2 append; never drain further pages here.
            if calibrated && self.active && self.tailVisible && snapshot.nextPage != nil {
                self.pages.loadMore(automatic: true)
            }
        }
    }
    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value; pages.setActive(value)
        if value {
            // A cancelled first read has no failure/retry button. A new visible tail may retry it
            // once; a real read failure keeps its explicit recovery contract.
            if !state.hasLoaded && state.failure == nil { automaticInitialAllowed = true }
            pages.tailExited()
        } else {
            tailVisible = false
        }
    }
    /// Only a successfully accepted home refresh discards already loaded catalogue pages.
    func reset() {
        pages.onChange = nil; pages.setActive(false)
        pages = Self.makePages(loader); state = pages.snapshot
        automaticInitialAllowed = true; tailVisible = false
        connect(); pages.setActive(active)
    }
    func loadMore(automatic: Bool = false) {
        guard active, state.operation == nil else { return }
        if state.hasLoaded {
            pages.loadMore(automatic: automatic)
        } else {
            guard !automatic || automaticInitialAllowed else { return }
            automaticInitialAllowed = false; pages.retry()
        }
    }
    func tailVisibilityChanged(_ visible: Bool) {
        guard visible != tailVisible else { return }
        tailVisible = visible
        if visible { loadMore(automatic: true) } else { pages.tailExited() }
    }
    func products(fallback: [HomeProductSummary]) -> [HomeProductSummary] {
        guard state.hasLoaded else { return fallback }
        return state.items.map {
            HomeProductSummary(
                id: $0.id, title: $0.title, subtitle: $0.subtitle, imageURL: $0.imageURL,
                priceYuan: $0.priceYuan, sold: $0.sold ?? 0)
        }
    }
}
