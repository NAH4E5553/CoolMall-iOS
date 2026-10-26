import Foundation
import MallCore
import Testing
@testable import MallData

struct CouponReceiverTests {
    private var base: URL {
        guard let value = URL(string: "https://coupon.invalid/app/") else {
            preconditionFailure("fixed fixture URL")
        }; return value
    }
    private func session(_ existing: Bool = true) -> SessionCoordinator {
        SessionCoordinator(
            loader: CouponAuthLoader(), storage: CouponAuthStorage(existing: existing),
            environmentURL: base)
    }
    @Test func exactWriteContractAndSuccessRequiresNonNullString() async throws {
        let transport = CouponTransport(data: Data("{\"code\":1000,\"data\":\"领取成功\"}".utf8))
        let receiver = HTTPCouponReceiver(
            environment: .init(baseURL: base), session: session(), transport: transport)
        try await receiver.receiveCoupon(accountID: 1, couponID: 860002)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/app/market/coupon/user/receive");
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "synthetic-session")
        struct Body: Decodable { let couponId: Int64 }
        let body = try JSONDecoder().decode(Body.self, from: #require(request.httpBody))
        #expect(body.couponId == 860002)
        let keys =
            try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
        #expect(keys?.count == 1); #expect(await transport.requests.count == 1)
    }
    @Test func serverMessagePreservesSuccessRejectionAndUnknownSemanticsWithoutReplay() async throws
    {
        let duplicate = "{\"code\":500,\"message\":\"已领取过该优惠券\"}"
        let cases: [(String, Int, CouponClaimFailure)] = [
            (duplicate, 200, .rejectedMessage(500, "已领取过该优惠券")),
            (duplicate, 500, .unconfirmed), (duplicate, 401, .authenticationRequired),
            ("{\"code\":501,\"message\":\"已领取过该优惠券\"}", 200, .rejectedMessage(501, "已领取过该优惠券")),
            ("{\"code\":500,\"message\":\"优惠券已领取完\"}", 200, .rejectedMessage(500, "优惠券已领取完")),
            ("{\"code\":500,\"message\":null}", 200, .rejected(500)),
            ("{\"code\":500,\"message\":{}}", 200, .rejected(500)),
            ("{\"code\":500,\"message\":\" \"}", 200, .rejected(500)),
            ("{\"code\":1000,\"message\":\"已领取过该优惠券\",\"data\":null}", 200, .unconfirmed),
        ]
        for (body, status, expected) in cases {
            let transport = CouponTransport(data: Data(body.utf8), status: status)
            let receiver = HTTPCouponReceiver(
                environment: .init(baseURL: base), session: session(), transport: transport)
            await #expect(throws: expected) {
                try await receiver.receiveCoupon(accountID: 1, couponID: 860003)
            }
            #expect(await transport.requests.count == 1)
        }
        for message in ["\"优惠券领取成功\"", "null", "{}", "\" \""] {
            let transport = CouponTransport(
                data: Data("{\"code\":1000,\"message\":\(message),\"data\":\"ok\"}".utf8))
            let receiver = HTTPCouponReceiver(
                environment: .init(baseURL: base), session: session(), transport: transport)
            let result = try await receiver.receiveCoupon(accountID: 1, couponID: 860003)
            #expect(result == (message == "\"优惠券领取成功\"" ? "优惠券领取成功" : nil))
            #expect(await transport.requests.count == 1)
        }
        for cancel in [false, true] {
            let session = session()
            let transport = CouponTransport(data: Data(duplicate.utf8), hold: true)
            let receiver = HTTPCouponReceiver(
                environment: .init(baseURL: base), session: session, transport: transport)
            let task = Task { try await receiver.receiveCoupon(accountID: 1, couponID: 860003) }
            await transport.started()
            if cancel { task.cancel() } else { try await session.logout() }
            await transport.release()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(await transport.requests.count == 1)
        }
    }
    @Test func preflightRejectsGuestIdentityEnvironmentAndInvalidCouponWithoutDispatch() async {
        let transport = CouponTransport(data: Data())
        let guest = HTTPCouponReceiver(
            environment: .init(baseURL: base), session: session(false), transport: transport)
        await #expect(throws: CouponClaimFailure.authenticationRequired) {
            try await guest.receiveCoupon(accountID: 1, couponID: 7)
        }
        let normal = HTTPCouponReceiver(
            environment: .init(baseURL: base), session: session(), transport: transport)
        await #expect(throws: CouponClaimFailure.authenticationRequired) {
            try await normal.receiveCoupon(accountID: 2, couponID: 7)
        }
        await #expect(throws: CouponClaimFailure.invalidConfiguration) {
            try await normal.receiveCoupon(accountID: 1, couponID: 0)
        }
        let wrong = HTTPCouponReceiver(
            environment: .init(baseURL: base.appending(path: "other/")), session: session(),
            transport: transport)
        await #expect(throws: CouponClaimFailure.invalidConfiguration) {
            try await wrong.receiveCoupon(accountID: 1, couponID: 7)
        }
        #expect(await transport.requests.isEmpty)
    }
    @Test func businessRejectionAndAmbiguousHTTPOrPayloadNeverBecomeSuccessOrReplay() async {
        let cases: [(String, Int, CouponClaimFailure)] = [
            ("{\"code\":1701,\"message\":\"opaque\"}", 200, .rejectedMessage(1701, "opaque")),
            ("{\"code\":401}", 200, .rejected(401)),
            ("{}", 401, .authenticationRequired), ("{}", 503, .unconfirmed),
            ("{\"code\":1000,\"data\":null}", 200, .unconfirmed),
            ("{\"code\":1000}", 200, .unconfirmed),
            ("{\"code\":1000,\"data\":true}", 200, .unconfirmed), ("broken", 200, .unconfirmed),
        ]
        for (body, status, failure) in cases {
            let transport = CouponTransport(data: Data(body.utf8), status: status)
            let receiver = HTTPCouponReceiver(
                environment: .init(baseURL: base), session: session(), transport: transport)
            await #expect(throws: failure) {
                try await receiver.receiveCoupon(accountID: 1, couponID: 7)
            }
            #expect(await transport.requests.count == 1)
        }
        let offline = CouponTransport(data: Data(), fail: true)
        let receiver = HTTPCouponReceiver(
            environment: .init(baseURL: base), session: session(), transport: offline)
        await #expect(throws: CouponClaimFailure.unconfirmed) {
            try await receiver.receiveCoupon(accountID: 1, couponID: 7)
        }
        #expect(await offline.requests.count == 1)
    }
    @Test func sharedAdapterRejectsConcurrentDuplicateAndReleasesOnlyCompletedOwnership()
        async throws
    {
        let transport = CouponTransport(
            data: Data("{\"code\":1000,\"data\":\"ok\"}".utf8), hold: true)
        let receiver = HTTPCouponReceiver(
            environment: .init(baseURL: base), session: session(), transport: transport)
        let first = Task { try await receiver.receiveCoupon(accountID: 1, couponID: 7) };
        await transport.started()
        await #expect(throws: CouponClaimFailure.busy) {
            try await receiver.receiveCoupon(accountID: 1, couponID: 7)
        }
        #expect(await transport.requests.count == 1)
        await transport.release(); _ = try await first.value
        let explicitNext = Task { try await receiver.receiveCoupon(accountID: 1, couponID: 7) };
        await transport.started()
        await transport.release(); _ = try await explicitNext.value
        #expect(await transport.requests.count == 2)
    }
    @Test func logoutReloginAndSwitchInvalidateLateSuccessAndErrorWithoutReplay() async throws {
        for change in ["logout", "same", "switch"] {
            for fail in [false, true] {
                let loader = CouponAuthLoader()
                let session = SessionCoordinator(
                    loader: loader, storage: CouponAuthStorage(existing: true), environmentURL: base
                )
                let transport = CouponTransport(
                    data: Data("{\"code\":1000,\"data\":\"ok\"}".utf8), hold: true, fail: fail)
                let receiver = HTTPCouponReceiver(
                    environment: .init(baseURL: base), session: session, transport: transport)
                let first = Task { try await receiver.receiveCoupon(accountID: 1, couponID: 7) };
                await transport.started()
                if change == "logout" {
                    try await session.logout()
                } else {
                    if change == "switch" { await loader.setID(2) }
                    try await session.login(.password(phone: "13800000000", password: "synthetic"))
                }
                await transport.release();
                await #expect(throws: CancellationError.self) { try await first.value }
                #expect(await transport.requests.count == 1)
            }
        }
    }
    @Test func cancellationAfterDispatchCannotClaimRollbackOrAutomaticallyResubmit() async {
        let transport = CouponTransport(
            data: Data("{\"code\":1000,\"data\":\"ok\"}".utf8), hold: true)
        let receiver = HTTPCouponReceiver(
            environment: .init(baseURL: base), session: session(), transport: transport)
        let first = Task { try await receiver.receiveCoupon(accountID: 1, couponID: 7) };
        await transport.started()
        first.cancel(); await transport.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await transport.requests.count == 1)
    }
}
