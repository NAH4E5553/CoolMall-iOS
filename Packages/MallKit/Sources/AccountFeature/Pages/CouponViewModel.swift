import Foundation
import MallCore
import Observation

@MainActor @Observable final class CouponViewModel {
    private let pages: NumberedPageCoordinator<UserCoupon>
    private(set) var state: NumberedPageSnapshot<UserCoupon>
    init(accountID: Int64, loader: any UserCouponsLoading, pageSize: Int = 10) {
        let pages = NumberedPageCoordinator<UserCoupon>(pageSize: pageSize) { page, size in
            try await loader.loadCoupons(accountID: accountID, page: page, pageSize: size)
        }
        self.pages = pages; state = pages.snapshot
        pages.onChange = { [weak self] in self?.state = $0 }
    }
    func activate(_ active: Bool) async {
        pages.setActive(active)
        if active { await pages.refresh() }
    }
    func stop() { pages.setActive(false) }
    func refresh() async { await pages.refresh() }
    func retry() { pages.retry() }
    func more(automatic: Bool = false) { pages.loadMore(automatic: automatic) }
    func tailExited() { pages.tailExited() }
    static func message(_ failure: PageReadFailure) -> String {
        switch failure {
        case .authenticationRequired: "请重新登录后查看优惠券"
        case .networkUnavailable: "网络连接失败，请重试"
        case .timeout: "请求超时，请重试"
        default: "优惠券读取失败，请重试"
        }
    }
}
