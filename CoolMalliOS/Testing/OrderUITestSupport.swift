#if DEBUG
    import Foundation
    import MallCore

    /// Explicit offline reads. No fake order is used by a normal Debug or Release launch.
    actor OrderUITestSupport: OrdersLoading, CheckoutLoading {
        private let mode: String
        private var attempts: [String: Int] = [:]
        private var contextAttempts = 0
        static func make(arguments: [String]) -> OrderUITestSupport? {
            guard let i = arguments.firstIndex(of: "--ui-orders") else { return nil }
            return OrderUITestSupport(
                mode: arguments.indices.contains(i + 1) ? arguments[i + 1] : "invalid")
        }
        init(mode: String) { self.mode = mode }
        func loadOrders(accountID: Int64, filter: OrderFilter, page: Int, pageSize: Int)
            async throws -> NumberedPage<OrderSnapshot>
        {
            guard accountID == 920001,
                ["success", "failure", "appendFailure", "empty", "contextFailure", "authFailure"]
                    .contains(mode)
            else { throw PageReadFailure.invalidConfiguration }
            let key = "\(filter.rawValue):\(page)"; attempts[key, default: 0] += 1
            if mode == "authFailure", page == 1, attempts[key] == 1 {
                throw PageReadFailure.authenticationRequired
            }
            if mode == "failure", page == 1, attempts[key] == 1 {
                throw PageReadFailure.networkUnavailable
            }
            if mode == "appendFailure", page == 2, attempts[key] == 1 {
                throw PageReadFailure.timeout
            }
            let values: [OrderSnapshot] =
                mode == "empty"
                ? []
                : (1...32).map { index in
                    Self.order(Int64(910000 + index), status: (index - 1) % 8)
                }.filter { filter.wireStatuses?.contains($0.status) ?? true }
            return NumberedPage(
                items: Array(values.dropFirst((page - 1) * pageSize).prefix(pageSize)), page: page,
                size: pageSize, total: Int64(values.count))
        }
        func loadOrder(accountID: Int64, orderID: Int64) async throws -> OrderSnapshot {
            guard accountID == 920001 else { throw PageReadFailure.authenticationRequired }
            return Self.order(orderID, status: Int(orderID - 910001) % 8)
        }
        func loadCheckout(accountID: Int64) async throws -> CheckoutContext {
            guard accountID == 920001 else { throw PageReadFailure.authenticationRequired }
            contextAttempts += 1
            if mode == "authFailure", contextAttempts == 1 {
                throw PageReadFailure.authenticationRequired
            }
            if mode == "contextFailure", contextAttempts == 1 {
                throw PageReadFailure.networkUnavailable
            }
            return CheckoutContext(
                defaultAddress: ShippingAddress(
                    id: 1,
                    value: ShippingAddressInput(
                        contact: "联系人1", phone: "13800000000", province: "北京市", city: "北京市",
                        district: "东城区", address: "测试街道1号", isDefault: true)),
                coupons: [
                    UserCoupon(
                        id: 701, title: "意向优惠券", description: "测试候选券", amountYuan: 30,
                        minimumSpendYuan: 299, startTime: "2020-01-01T00:00:00Z",
                        endTime: "2030-01-01T00:00:00Z", type: 0, status: 1, useStatus: 0)
                ])
        }
        private static func order(_ id: Int64, status: Int) -> OrderSnapshot {
            OrderSnapshot(
                id: id, number: "TEST-\(id)", status: status, title: "测试订单",
                createdAt: "2026-10-26 12:00:00", paidAt: nil,
                address: OrderAddressSnapshot(
                    contact: "历史联系人", phone: "13800000000", location: "北京市 历史街道"),
                lines: [
                    OrderLineSnapshot(
                        id: id * 10, title: "历史订单商品", specification: "黑色 256GB", imageURL: nil,
                        quantity: 2)
                ])
        }
    }
#endif
