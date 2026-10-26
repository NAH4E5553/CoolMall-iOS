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
}
