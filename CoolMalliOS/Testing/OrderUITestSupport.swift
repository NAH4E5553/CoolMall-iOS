#if DEBUG
    import Foundation
    import MallCore

    /// Explicit offline reads. No fake order is used by a normal Debug or Release launch.
    actor OrderUITestSupport: OrdersLoading, CheckoutLoading, OrderCreating, OrderCancelling {
        private var created: [Int64: OrderSnapshot] = [:]
        private var createdIntents: [UUID: Int64] = [:]
        private var closed: Set<Int64> = []
        private var closeReasons: [Int64: String] = [:]
        private var reasonAttempts = 0
        private var unknownCreates: Set<UUID> = []
        func createOrder(accountID: Int64, input: OrderCreation) async throws -> Int64 {
            guard accountID == 920001 else { throw OrderWriteFailure.authenticationRequired }
            if mode == "createRejected" {
                throw OrderWriteFailure.rejected(code: 500, message: "库存不足，请重新选择")
            }
            if mode == "createUnknown" {
                unknownCreates.insert(input.intent.id); throw OrderWriteFailure.unconfirmed
            }
            if let id = createdIntents[input.intent.id] { return id }
            let id: Int64 = 990001 + Int64(created.count)
            let estimate = try CheckoutEstimate(
                subtotalYuan: input.intent.subtotalYuan, coupon: input.coupon)
            created[id] = OrderSnapshot(
                id: id, number: "TEST-\(id)", status: 0, title: input.intent.title,
                createdAt: "2026-10-26 12:00:00", paidAt: nil,
                address: OrderAddressSnapshot(
                    contact: "联系人1", phone: "13800000000", location: "北京市 北京市 东城区 测试街道1号",
                    isDefault: true),
                lines: [
                    OrderLineSnapshot(
                        id: id * 10, title: input.intent.title,
                        specification: input.intent.specification,
                        imageURL: input.intent.imageURL, quantity: input.intent.quantity,
                        unitPriceYuan: input.intent.unitPriceYuan)
                ],
                amounts: try OrderAmounts(
                    subtotalYuan: input.intent.subtotalYuan, discountYuan: estimate.discountYuan),
                remark: input.remark)
            createdIntents[input.intent.id] = id; return id
        }
        func loadCancelReasons(accountID: Int64) async throws -> [OrderCancelReason] {
            guard accountID == 920001 else { throw OrderWriteFailure.authenticationRequired }
            reasonAttempts += 1
            if mode == "reasonAuthFailure", reasonAttempts == 1 {
                throw PageReadFailure.authenticationRequired
            }
            return (1...9).map {
                OrderCancelReason(id: Int64($0), name: $0 == 1 ? "不想要了" : "测试取消原因\($0)")
            }
        }
        func cancelOrder(accountID: Int64, orderID: Int64, reason: OrderCancelReason) async throws {
            guard accountID == 920001 else { throw OrderWriteFailure.authenticationRequired }
            closed.insert(orderID); closeReasons[orderID] = reason.name
        }
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
                [
                    "success", "failure", "appendFailure", "empty", "contextFailure", "authFailure",
                    "createRejected", "createUnknown", "reasonAuthFailure", "checkoutSparseCoupon",
                ]
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
                    Self.order(
                        Int64(910000 + index),
                        status: closed.contains(Int64(910000 + index)) ? 7 : (index - 1) % 8)
                }.filter { filter.wireStatuses?.contains($0.status) ?? true }
            return NumberedPage(
                items: Array(values.dropFirst((page - 1) * pageSize).prefix(pageSize)), page: page,
                size: pageSize, total: Int64(values.count))
        }
        func loadOrder(accountID: Int64, orderID: Int64) async throws -> OrderSnapshot {
            guard accountID == 920001 else { throw PageReadFailure.authenticationRequired }
            if let order = created[orderID] {
                return OrderSnapshot(
                    id: order.id, number: order.number,
                    status: closed.contains(orderID) ? 7 : order.status,
                    title: order.title, createdAt: order.createdAt, paidAt: order.paidAt,
                    address: order.address,
                    lines: order.lines, amounts: mode == "missingMoney" ? nil : order.amounts,
                    payType: order.payType,
                    remark: order.remark, closeRemark: closeReasons[orderID])
            }
            return Self.order(
                orderID, status: closed.contains(orderID) ? 7 : Int(orderID - 910001) % 8)
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
                        endTime: "2030-01-01T00:00:00Z", type: 0, status: 1, useStatus: 0),
                    UserCoupon(
                        id: 702, title: "家电优惠券", description: "测试规则", amountYuan: 80,
                        minimumSpendYuan: 999, startTime: "2020-01-01T00:00:00Z",
                        endTime: "2030-01-01T00:00:00Z", type: 0, status: 1, useStatus: 0),
                    UserCoupon(
                        id: 703, title: "数码优惠券", description: "测试规则", amountYuan: 150,
                        minimumSpendYuan: 1999, startTime: "2020-01-01T00:00:00Z",
                        endTime: "2030-01-01T00:00:00Z", type: 0, status: 1, useStatus: 0),
                    UserCoupon(
                        id: 704, title: "额外优惠券", description: "测试规则", amountYuan: 10,
                        minimumSpendYuan: 299, startTime: "2020-01-01T00:00:00Z",
                        endTime: "2030-01-01T00:00:00Z", type: 0, status: 1, useStatus: 0),
                ].map { coupon in
                    guard mode == "checkoutSparseCoupon" else { return coupon }
                    return UserCoupon(
                        id: coupon.id, title: coupon.title,
                        description: coupon.description, amountYuan: coupon.amountYuan,
                        minimumSpendYuan: coupon.id == 704 ? 9999 : coupon.minimumSpendYuan,
                        startTime: nil, endTime: nil, type: nil, status: nil, useStatus: nil,
                        availabilityContext: .checkoutCandidate)
                })
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
                        quantity: 2, unitPriceYuan: 3999),
                    OrderLineSnapshot(
                        id: id * 10 + 1, title: "第二件历史商品", specification: "白色", imageURL: nil,
                        quantity: 1, unitPriceYuan: 99),
                ], amounts: try? OrderAmounts(subtotalYuan: 8097, discountYuan: 30), payType: 0)
        }
    }
#endif
