import Foundation
import MallCore
import Testing
@testable import MallData

struct OrderTransactionTests {
    private let base = URL(string: "https://coupon.invalid/app/")!
    private func session() -> SessionCoordinator {
        SessionCoordinator(
            loader: CouponAuthLoader(), storage: CouponAuthStorage(existing: true),
            environmentURL: base)
    }
    private func input(price: Decimal = 999) throws -> OrderCreation {
        let image = URL(string: "https://images.invalid/product.png")!
        return OrderCreation(
            intent: try BuyNowIntent(
                product: ProductDetailSnapshot(
                    id: 9, title: "商品", subtitle: nil, priceYuan: price,
                    sold: 0, isAvailable: true, imageURLs: [image], contentImageURLs: []),
                specification: ProductSpecification(
                    id: 4, productID: 9, name: "黑色", priceYuan: price,
                    stock: 3, imageURLs: [image.appendingPathComponent("sku")]), quantity: 2),
            addressID: 8, coupon: nil, remark: "请联系")
    }
    private func service(_ transport: CouponTransport, session: SessionCoordinator? = nil)
        -> HTTPOrderTransactions
    {
        HTTPOrderTransactions(
            environment: .init(baseURL: base), session: session ?? self.session(),
            transport: transport)
    }
    @Test func exactSelectedSnapshotAndKnownIdentityDoNotCreateTwice() async throws {
        let transport = CouponTransport(data: Data(#"{"code":1000,"data":{"id":71}}"#.utf8))
        let service = service(transport), input = try input()
        #expect(try await service.createOrder(accountID: 1, input: input) == 71)
        #expect(try await service.createOrder(accountID: 1, input: input) == 71)
        let request = try #require(await transport.requests.first)
        #expect(await transport.requests.count == 1)
        #expect(request.url?.path == "/app/order/info/create")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(json["data"] as? [String: Any])
        #expect(data["addressId"] as? Int == 8); #expect(data["remark"] as? String == "请联系")
        // An untouched coupon selection means no coupon ID is sent.
        #expect(data["couponId"] == nil)
        let line = try #require((data["goodsList"] as? [[String: Any]])?.first)
        #expect(line["count"] as? Int == 2); #expect(line["specId"] == nil)
        let spec = try #require(line["spec"] as? [String: Any])
        #expect(spec["stock"] as? Int == 3); #expect(spec["price"] as? Int == 999)
        #expect(
            (spec["images"] as? [String])?.first
                == input.intent.specificationImages.first?.absoluteString)
        #expect(
            (line["goodsInfo"] as? [String: Any])?["mainPic"] as? String
                == input.intent.productImageURL?.absoluteString)
    }
    @Test func knownIdentityWinsOverChangedOrInvalidInputOnRecovery() async throws {
        let transport = CouponTransport(data: Data(#"{"code":1000,"data":{"id":71}}"#.utf8))
        let service = service(transport), original = try input()
        #expect(try await service.createOrder(accountID: 1, input: original) == 71)
        let changed = OrderCreation(
            intent: original.intent, addressID: 0, coupon: nil, remark: "changed")
        #expect(try await service.createOrder(accountID: 1, input: changed) == 71)
        #expect(await transport.requests.count == 1)
    }
    @Test func missingOrWrongIdentityAndHTTPTimeoutLockSameAttempt() async throws {
        for (body, status) in [
            (#"{"code":1000,"data":{}}"#, 200),
            (#"{"code":1000,"data":{"id":71,"userId":2}}"#, 200), ("", 500),
        ] {
            let transport = CouponTransport(data: Data(body.utf8), status: status)
            let service = service(transport), input = try input()
            for _ in 0..<2 {
                await #expect(throws: OrderWriteFailure.unconfirmed) {
                    try await service.createOrder(accountID: 1, input: input)
                }
            }
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func businessMessageIsShownAndDefiniteRejectionAllowsExplicitRetry() async throws {
        let transport = CouponTransport(data: Data(#"{"code":500,"message":"库存不足"}"#.utf8))
        let service = service(transport), input = try input()
        for _ in 0..<2 {
            await #expect(throws: OrderWriteFailure.rejected(code: 500, message: "库存不足")) {
                try await service.createOrder(accountID: 1, input: input)
            }
        }
        #expect(await transport.requests.count == 2)
    }
    @Test func preflightInvalidAddressFractionalWirePriceAndGuestSendNothing() async throws {
        let transport = CouponTransport(data: Data()), service = service(transport)
        let valid = try input()
        await #expect(throws: OrderWriteFailure.invalidInput) {
            try await service.createOrder(
                accountID: 1,
                input: OrderCreation(intent: valid.intent, addressID: 0, coupon: nil, remark: ""))
        }
        await #expect(throws: OrderWriteFailure.invalidInput) {
            try await service.createOrder(
                accountID: 1, input: self.input(price: Decimal(string: "1.23")!))
        }
        await #expect(throws: OrderWriteFailure.authenticationRequired) {
            try await service.createOrder(accountID: 2, input: valid)
        }
        #expect(await transport.requests.isEmpty)
    }
    @Test func simultaneousCreateIsSingleFlightAndCancelledWaitLocksUnknownOutcome() async throws {
        let transport = CouponTransport(
            data: Data(#"{"code":1000,"data":{"id":71}}"#.utf8), hold: true)
        let service = service(transport), input = try input()
        let task = Task { try await service.createOrder(accountID: 1, input: input) }
        await transport.started()
        await #expect(throws: OrderWriteFailure.busy) {
            try await service.createOrder(accountID: 1, input: input)
        }
        task.cancel(); await transport.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        await #expect(throws: OrderWriteFailure.unconfirmed) {
            try await service.createOrder(accountID: 1, input: input)
        }
        #expect(await transport.requests.count == 1)
    }
    @Test func logoutRejectsLateSuccessAndCannotReuseKnownIDUnauthenticated() async throws {
        let transport = CouponTransport(
            data: Data(#"{"code":1000,"data":{"id":71}}"#.utf8), hold: true)
        let session = session(), service = service(transport, session: session), input = try input()
        let task = Task { try await service.createOrder(accountID: 1, input: input) }
        await transport.started(); try await session.logout(); await transport.release()
        await #expect(throws: OrderWriteFailure.authenticationRequired) { try await task.value }
        await #expect(throws: OrderWriteFailure.authenticationRequired) {
            try await service.createOrder(accountID: 1, input: input)
        }
        #expect(await transport.requests.count == 1)
    }
    @Test func sameAccountNewSessionRejectsOldLateReceiptButCanReadItsEstablishedIdentity()
        async throws
    {
        let transport = CouponTransport(
            data: Data(#"{"code":1000,"data":{"id":71}}"#.utf8), hold: true)
        let session = session(), service = service(transport, session: session), input = try input()
        let task = Task { try await service.createOrder(accountID: 1, input: input) }
        await transport.started()
        try await session.login(.password(phone: "13800000000", password: "test-only"))
        await transport.release()
        await #expect(throws: OrderWriteFailure.authenticationRequired) { try await task.value }
        #expect(try await service.knownCreatedOrder(accountID: 1, intentID: input.intent.id) == 71)
        #expect(await transport.requests.count == 1)
    }
    @Test func cancellationRequiresTrueAndLocksUnknownResponses() async throws {
        for data in ["false", "null", "{}", "\"true\""] {
            let transport = CouponTransport(
                data: Data((#"{"code":1000,"data":"# + data + "}").utf8))
            let service = service(transport)
            for _ in 0..<2 {
                await #expect(throws: OrderWriteFailure.unconfirmed) {
                    try await service.cancelOrder(
                        accountID: 1, orderID: 71, reason: .init(id: 1, name: "不想要了"))
                }
            }
            #expect(await transport.requests.count == 1)
        }
        let transport = CouponTransport(data: Data(#"{"code":1000,"data":true}"#.utf8)),
            service = service(transport)
        for _ in 0..<2 {
            try await service.cancelOrder(
                accountID: 1, orderID: 71, reason: .init(id: 1, name: "不想要了"))
        }
        #expect(await transport.requests.count == 1)
        let body = try #require(await transport.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["orderId"] as? Int == 71); #expect(json["remark"] as? String == "不想要了")
    }
    @Test func HTTPAuthenticationFailureRequestsLoginWhilePreservingUnknownWriteLock() async throws
    {
        for status in [401, 403] {
            let transport = CouponTransport(data: Data(), status: status),
                service = service(transport)
            let input = try input()
            await #expect(throws: OrderWriteFailure.authenticationRequired) {
                try await service.createOrder(accountID: 1, input: input)
            }
            await #expect(throws: OrderWriteFailure.unconfirmed) {
                try await service.createOrder(accountID: 1, input: input)
            }
            #expect(await transport.requests.count == 1)
            let cancelTransport = CouponTransport(data: Data(), status: status),
                cancelling = self.service(cancelTransport)
            let reason = OrderCancelReason(id: 1, name: "原因")
            await #expect(throws: OrderWriteFailure.authenticationRequired) {
                try await cancelling.cancelOrder(accountID: 1, orderID: 71, reason: reason)
            }
            await #expect(throws: OrderWriteFailure.unconfirmed) {
                try await cancelling.cancelOrder(accountID: 1, orderID: 71, reason: reason)
            }
            #expect(await cancelTransport.requests.count == 1)
        }
    }
    @Test func reasonDictionaryHasNoHardcodedFallback() async throws {
        let transport = CouponTransport(
            data: Data(#"{"code":1000,"data":{"orderCancelReason":[{"id":9,"name":"后端原因"}]}}"#.utf8)
        )
        let values = try await service(transport).loadCancelReasons(accountID: 1)
        #expect(values == [.init(id: 9, name: "后端原因")])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/app/dict/info/data")
        #expect(request.httpBody == Data(#"{"types":["orderCancelReason"]}"#.utf8))
        await #expect(throws: PageReadFailure.invalidResponse) {
            try await self.service(CouponTransport(data: Data(#"{"code":1000,"data":{}}"#.utf8)))
                .loadCancelReasons(accountID: 1)
        }
    }
    @Test func authoritativeOrderMoneyIsOptionalAndInvalidAmountsDoNotBecomeZero() async throws {
        for amounts in [
            "", #", "price":100"#, #", "price":100,"discountPrice":101"#,
            #", "price":-1,"discountPrice":0"#,
        ] {
            let bytes = Data((#"{"code":1000,"data":{"id":71,"status":0"# + amounts + "}}").utf8)
            let reader = HTTPOrderService(
                environment: .init(baseURL: base), session: session(),
                transport: CouponTransport(data: bytes))
            #expect(try await reader.loadOrder(accountID: 1, orderID: 71).amounts == nil)
        }
        let bytes = Data(
            #"{"code":1000,"data":{"id":71,"status":0,"price":5499,"discountPrice":30}}"#.utf8)
        let reader = HTTPOrderService(
            environment: .init(baseURL: base), session: session(),
            transport: CouponTransport(data: bytes))
        #expect(try await reader.loadOrder(accountID: 1, orderID: 71).amounts?.payableYuan == 5469)
    }
}
