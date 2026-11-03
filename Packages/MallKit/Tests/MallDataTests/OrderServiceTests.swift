import Foundation
import MallCore
import Testing
@testable import MallData

struct OrderServiceTests {
    private let base = URL(string: "https://coupon.invalid/app/")!
    private func session() -> SessionCoordinator {
        SessionCoordinator(
            loader: CouponAuthLoader(), storage: CouponAuthStorage(existing: true),
            environmentURL: base)
    }
    private func service(_ transport: CouponTransport, session: SessionCoordinator? = nil)
        -> HTTPOrderService
    {
        HTTPOrderService(
            environment: .init(baseURL: base), session: session ?? self.session(),
            transport: transport)
    }
    private let row =
        #"{"id":7,"status":3,"userId":1,"orderNum":"TEST","goodsList":[{"id":71,"orderId":7,"count":2}]}"#
    private func page(_ row: String, total: Int = 1) -> Data {
        Data(
            (#"{"code":1000,"data":{"list":["# + row
                + #"],"pagination":{"page":1,"size":10,"total":"# + String(total) + "}}}").utf8)
    }
    @Test func allFiltersEncodeWireValuesNotIndicesAndOnlyReadAllowlistIsDispatched() async throws {
        let transport = CouponTransport(data: page(row)); let service = service(transport)
        for filter in OrderFilter.allCases {
            let result = try await service.loadOrders(
                accountID: 1, filter: filter, page: 1, pageSize: 10)
            #expect(result.items.first?.status == 3)
        }
        let requests = await transport.requests
        for (filter, request) in zip(OrderFilter.allCases, requests) {
            #expect(request.httpMethod == "POST");
            #expect(request.url?.path == "/app/order/info/page")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "synthetic-session")
            let body = try #require(request.httpBody)
            let json = try JSONSerialization.jsonObject(with: body)
            let query = try #require(json as? [String: Any])
            #expect(query["page"] as? Int == 1); #expect(query["size"] as? Int == 10)
            #expect(query["status"] as? [Int] == filter.wireStatuses)
            #expect(query.count == (filter == .all ? 2 : 3))
        }
        let info = CouponTransport(data: Data((#"{"code":1000,"data":"# + row + "}").utf8))
        let order = try await self.service(info).loadOrder(accountID: 1, orderID: 7)
        #expect(order.lines?.first?.title == nil); #expect(order.lines?.first?.quantity == 2)
        let request = try #require(await info.requests.first)
        #expect(request.httpMethod == "GET"); #expect(request.url?.path == "/app/order/info/info")
        #expect(request.url?.query == "id=7"); #expect(request.httpBody == nil)
    }
    @Test func requiredFieldsIdentityDuplicateRowsAndMalformedPagesNeverBecomeEmptySuccess()
        async throws
    {
        let invalid = [
            #"{"id":0,"status":0}"#, #"{"id":7}"#, #"{"status":0}"#,
            #"{"id":7,"status":3,"userId":2}"#,
            #"{"id":7,"status":3,"goodsList":[{"id":71,"count":0}]}"#,
            #"{"id":7,"status":3,"goodsList":[{"id":71,"count":1},{"id":71,"count":2}]}"#,
        ]
        for row in invalid {
            await #expect(throws: PageReadFailure.invalidResponse) {
                try await service(CouponTransport(data: page(row))).loadOrders(
                    accountID: 1, filter: .all, page: 1, pageSize: 10)
            }
        }
        await #expect(throws: PageReadFailure.invalidResponse) {
            try await service(CouponTransport(data: page(row, total: 2))).loadOrders(
                accountID: 1, filter: .all, page: 1, pageSize: 10)
        }
        await #expect(throws: PageReadFailure.invalidResponse) {
            try await service(
                CouponTransport(data: Data((#"{"code":1000,"data":"# + row + "}").utf8))
            ).loadOrder(accountID: 1, orderID: 8)
        }
    }
    @Test func unknownStatusAndOptionalHistoricalSnapshotsRemainHonest() async throws {
        let body =
            #"{"code":1000,"data":{"id":7,"status":91,"address":{"contact":"历史","address":"旧街道"},"goodsList":null}}"#
        let value = try await service(CouponTransport(data: Data(body.utf8))).loadOrder(
            accountID: 1, orderID: 7)
        #expect(value.status == 91); #expect(value.lines == nil); #expect(value.number == nil)
        #expect(value.address?.location == "旧街道"); #expect(value.address?.contact == "历史")
    }
    @Test func confirmationIsContextOnlyNoQuoteParametersAndNullableCandidatesStayUnknown()
        async throws
    {
        let transport = CouponTransport(
            data: Data(#"{"code":1000,"data":{"defaultAddress":null,"userCoupon":null}}"#.utf8))
        let context = try await service(transport).loadCheckout(accountID: 1)
        #expect(context.defaultAddress == nil); #expect(context.coupons == nil)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET"); #expect(request.url?.path == "/app/page/confirmOrder")
        #expect(request.url?.query == nil); #expect(request.httpBody == nil)
    }
    @Test func guestsInvalidInputBusinessAndHTTPFailuresRemainDistinct() async {
        let transport = CouponTransport(data: Data()); let service = service(transport)
        await #expect(throws: PageReadFailure.authenticationRequired) {
            try await service.loadCheckout(accountID: 0)
        }
        await #expect(throws: PageReadFailure.authenticationRequired) {
            try await service.loadOrder(accountID: 2, orderID: 7)
        }
        await #expect(throws: PageReadFailure.invalidConfiguration) {
            try await service.loadOrder(accountID: 1, orderID: 0)
        }
        #expect(await transport.requests.isEmpty)
        await #expect(throws: PageReadFailure.businessCode(500)) {
            try await self.service(
                CouponTransport(data: Data(#"{"code":500,"message":"拒绝"}"#.utf8))
            ).loadCheckout(accountID: 1)
        }
        await #expect(throws: PageReadFailure.authenticationRequired) {
            try await self.service(CouponTransport(data: Data(), status: 401)).loadCheckout(
                accountID: 1)
        }
    }
    @Test func logoutAndCancellationRejectLateSuccessAndLateFailure() async throws {
        for fail in [false, true] {
            let session = session();
            let transport = CouponTransport(
                data: Data((#"{"code":1000,"data":"# + row + "}").utf8), hold: true, fail: fail)
            let service = service(transport, session: session)
            let task = Task { try await service.loadOrder(accountID: 1, orderID: 7) }
            await transport.started(); try await session.logout(); await transport.release()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        let transport = CouponTransport(
            data: Data(#"{"code":1000,"data":{"userCoupon":[]}}"#.utf8), hold: true)
        let service = service(transport);
        let task = Task { try await service.loadCheckout(accountID: 1) }
        await transport.started(); task.cancel(); await transport.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func confirmationProjectionPreservesMissingFieldsWithoutDisablingEveryCandidate()
        async throws
    {
        let rows = (1...3).map { index in
            "{\"id\":\(index),\"title\":\"coupon\",\"description\":\"rules\",\"amount\":30,\"condition\":{\"fullAmount\":299}}"
        }.joined(separator: ",")
        let bytes = Data(("{\"code\":1000,\"data\":{\"userCoupon\":[" + rows + "]}}").utf8)
        let context = try await service(CouponTransport(data: bytes)).loadCheckout(accountID: 1)
        let candidates = try #require(context.coupons)
        #expect(candidates.count == 3)
        for coupon in candidates {
            #expect(coupon.availabilityContext == .checkoutCandidate)
            #expect(coupon.availability() == .available)
            #expect(coupon.useStatus == nil); #expect(coupon.endTime == nil)
            #expect(coupon.type == nil); #expect(coupon.status == nil)
            #expect(coupon.minimumSpendYuan == 299)
        }
        let ownedBytes = Data(
            ("{\"code\":1000,\"data\":{\"list\":[" + rows
                + "],\"pagination\":{\"page\":1,\"size\":10,\"total\":3}}}").utf8)
        let owned = try await HTTPUserCouponService(
            environment: .init(baseURL: base),
            session: session(), transport: CouponTransport(data: ownedBytes)
        )
        .loadCoupons(accountID: 1, page: 1, pageSize: 10)
        #expect(owned.items.count == 3)
        #expect(
            owned.items.allSatisfy {
                $0.availabilityContext == .owned && $0.availability() == .unverified
            })
        // The Android model specifically documents useStatus as owned-page-only.
        let missingUseStatus = Data(
            #"{"code":1000,"data":{"userCoupon":[{"id":7,"title":"coupon","description":"rules","amount":30,"condition":{"fullAmount":299},"type":0,"status":1,"startTime":"2020-01-01T00:00:00Z","endTime":"2030-01-01T00:00:00Z"}]}}"#
                .utf8)
        let usual = try await service(CouponTransport(data: missingUseStatus)).loadCheckout(
            accountID: 1)
        let usualCoupon = try #require(usual.coupons?.first)
        #expect(usualCoupon.useStatus == nil)
        #expect(usualCoupon.availability() == .available)
        #expect(try CheckoutEstimate(subtotalYuan: 299, coupon: usualCoupon).totalYuan == 269)

    }

    @Test func countReadUsesExactEndpointAuthorizationAndChineseKeys() async throws {
        let transport = CouponTransport(
            data: Data(
                #"{"code":1000,"data":{"待付款":101,"待发货":0,"待收货":3,"待评价":4,"退款中":5,"已退款":6}}"#.utf8))
        let counts = try await service(transport).loadOrderCounts(accountID: 1)
        #expect(counts.unpaid == 101); #expect(counts.unshipped == 0)
        #expect(counts.unreceived == 3); #expect(counts.unevaluated == 4)
        #expect(counts.afterSale == 11)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET"); #expect(request.httpBody == nil)
        #expect(request.url?.path == "/app/order/info/userCount");
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "synthetic-session")
        let partial = try await service(
            CouponTransport(data: Data(#"{"code":1000,"data":{"待付款":0,"退款中":3}}"#.utf8))
        ).loadOrderCounts(accountID: 1)
        #expect(partial.unpaid == 0); #expect(partial.unshipped == nil);
        #expect(partial.afterSale == nil)
    }
    @Test func countReadRejectsMalformedNegativeBusinessAndUnauthenticatedResponses() async {
        for body in [
            #"{"code":1000,"data":{"待付款":-1}}"#,
            #"{"code":1000,"data":{"待付款":"3"}}"#,
            #"{"code":1000,"data":{"退款中":9223372036854775807,"已退款":1}}"#,
            #"{"code":1000,"data":null}"#,
        ] {
            await #expect(throws: PageReadFailure.invalidResponse) {
                try await service(CouponTransport(data: Data(body.utf8))).loadOrderCounts(
                    accountID: 1)
            }
        }
        let transport = CouponTransport(data: Data()); let reader = service(transport)
        for id: Int64 in [0, 2] {
            await #expect(throws: PageReadFailure.authenticationRequired) {
                try await reader.loadOrderCounts(accountID: id)
            }
        }
        #expect(await transport.requests.isEmpty)
        await #expect(throws: PageReadFailure.businessCode(500)) {
            try await service(CouponTransport(data: Data(#"{"code":500,"message":"拒绝"}"#.utf8)))
                .loadOrderCounts(accountID: 1)
        }
        await #expect(throws: PageReadFailure.authenticationRequired) {
            try await service(CouponTransport(data: Data(), status: 401)).loadOrderCounts(
                accountID: 1)
        }
    }
    @Test func countReadLogoutAndCancellationRejectLateReplies() async throws {
        for fail in [false, true] {
            let session = session()
            let transport = CouponTransport(
                data: Data(#"{"code":1000,"data":{"待付款":3}}"#.utf8), hold: true, fail: fail)
            let reader = service(transport, session: session)
            let task = Task { try await reader.loadOrderCounts(accountID: 1) }
            await transport.started(); try await session.logout(); await transport.release()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        let transport = CouponTransport(data: Data(#"{"code":1000,"data":{}}"#.utf8), hold: true)
        let reader = service(transport);
        let task = Task { try await reader.loadOrderCounts(accountID: 1) }
        await transport.started(); task.cancel(); await transport.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

}
