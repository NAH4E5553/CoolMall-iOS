import MallCore
import Foundation
import Observation

@MainActor @Observable final class CouponProductsViewModel {
    private let pages: NumberedPageCoordinator<CouponProductSummary>
    private(set) var state: NumberedPageSnapshot<CouponProductSummary>
    init(minimum: Decimal?, loader: any CouponProductsLoading, pageSize: Int = 20) {
        let pages = NumberedPageCoordinator<CouponProductSummary>(pageSize: pageSize) {
            page, size in
            try await loader.loadProducts(minimumPriceYuan: minimum, page: page, pageSize: size)
        }
        self.pages = pages; state = pages.snapshot
        pages.onChange = { [weak self] in self?.state = $0 }
    }
    func activate(_ active: Bool) async {
        pages.setActive(active)
        if active { await pages.loadInitial() }
    }
    func stop() { pages.setActive(false) }
    func refresh() async { await pages.refresh() }
    func retry() { pages.retry() }
    func more(automatic: Bool = false) { pages.loadMore(automatic: automatic) }
    func tailExited() { pages.tailExited() }
}
