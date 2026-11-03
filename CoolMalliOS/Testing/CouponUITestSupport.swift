#if DEBUG
    import Foundation
    import MallCore

    actor CouponUITestSupport: UserCouponsLoading, CouponProductsLoading, CouponReceiving {
        private let scenario: String
        private var claimed: Set<Int64> = []
        private var claimCalls = 0
        private var reads = 0
        private var appendFailed = false
        init(scenario: String) { self.scenario = scenario }
        nonisolated static func make(arguments: [String]) -> CouponUITestSupport? {
            guard let index = arguments.firstIndex(of: "--ui-coupons") else { return nil }
            return CouponUITestSupport(
                scenario: arguments.indices.contains(index + 1) ? arguments[index + 1] : "invalid")
        }
        func loadCoupons(accountID: Int64, page: Int, pageSize: Int) async throws -> NumberedPage<
            UserCoupon
        > {
            try Task.checkCancellation()
            guard accountID == 920001,
                [
                    "success", "empty", "initialFailure", "refreshFailure", "appendFailure",
                    "appendAuthFailure", "receiveSuccess", "receiveReject", "receiveUnknown",
                    "receivePending", "receiveAuthFailure", "receiveMessage",
                ].contains(
                    scenario)
            else { throw PageReadFailure.invalidConfiguration }
            if scenario.hasPrefix("receive") {
                let ids = claimed.sorted(); let offset = (page - 1) * pageSize
                let items = ids.dropFirst(offset).prefix(pageSize).map { id in
                    UserCoupon(
                        id: id, title: "已领取优惠券 \(id)", description: "夹具领取成功后的真实读取路径",
                        amountYuan: 30,
                        minimumSpendYuan: 299, startTime: "2020-01-01T00:00:00",
                        endTime: "2030-01-01T00:00:00", type: 0, status: 1, useStatus: 0)
                }
                return NumberedPage(
                    items: Array(items), page: page, size: pageSize, total: Int64(ids.count))
            }
            reads += 1
            if scenario == "initialFailure" && reads == 1
                || scenario == "refreshFailure" && reads == 2
            {
                throw PageReadFailure.networkUnavailable
            }
            if (scenario == "appendFailure" || scenario == "appendAuthFailure") && page == 2
                && !appendFailed
            {
                appendFailed = true;
                throw scenario == "appendAuthFailure"
                    ? PageReadFailure.authenticationRequired : PageReadFailure.timeout
            }
            let total =
                scenario == "empty"
                ? 0 : ["appendFailure", "appendAuthFailure"].contains(scenario) ? 12 : 3
            let offset = (page - 1) * pageSize
            let items = (min(offset, total)..<min(offset + pageSize, total)).map { index in
                UserCoupon(
                    id: Int64(701 + index), title: "【满减券】小米精选满299减30元 \(index + 1)",
                    description: "小米商城精选商品可用，部分商品除外", amountYuan: Decimal(string: "30.25") ?? 30,
                    minimumSpendYuan: 299, startTime: "2020-01-01T00:00:00",
                    endTime: "2030-01-01T00:00:00", type: 0, status: 1,
                    useStatus: index == 2 ? 1 : 0)
            }
            return NumberedPage(items: items, page: page, size: pageSize, total: Int64(total))
        }
        func receiveCoupon(accountID: Int64, couponID: Int64) async throws -> String? {
            guard accountID == 920001, couponID > 0, scenario.hasPrefix("receive") else {
                throw CouponClaimFailure.invalidConfiguration
            }
            claimCalls += 1
            if scenario == "receiveAuthFailure" && claimCalls == 1 {
                throw CouponClaimFailure.authenticationRequired
            }
            if scenario == "receivePending" { try await Task.sleep(for: .seconds(100)) }
            if scenario == "receiveUnknown" { throw CouponClaimFailure.unconfirmed }
            if scenario == "receiveReject" && claimCalls == 1 {
                throw CouponClaimFailure.rejected(1701)
            }
            if scenario == "receiveMessage" && claimCalls == 1 {
                throw CouponClaimFailure.rejectedMessage(500, "已领取过该优惠券")
            }
            try Task.checkCancellation(); claimed.insert(couponID)
            return scenario == "receiveMessage" ? "优惠券领取成功" : nil
        }
        func loadProducts(minimumPriceYuan: Decimal?, page: Int, pageSize: Int) async throws
            -> NumberedPage<CouponProductSummary>
        {
            guard minimumPriceYuan == 299 else { throw PageReadFailure.invalidConfiguration }
            return NumberedPage(
                items: page == 1
                    ? [
                        CouponProductSummary(
                            id: 830001, title: "价格门槛299元商品", subtitle: "按价格浏览", imageURL: nil,
                            priceYuan: 399, sold: 7)
                    ] : [], page: page, size: pageSize, total: 1)
        }
    }
#endif
