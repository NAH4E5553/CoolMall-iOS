import Foundation
import MallCore
import Testing
@testable import MallData

struct CouponServiceTests {
    private var base: URL {
        guard let url = URL(string: "https://coupon.invalid/app/") else {
            preconditionFailure("fixed test URL")
        }; return url
    }
    private func session(existing: Bool = true) -> SessionCoordinator {
        SessionCoordinator(
            loader: CouponAuthLoader(), storage: CouponAuthStorage(existing: existing),
            environmentURL: base)
    }
    private func data(
        _ list: String = Self.couponJSON, page: Int = 1, size: Int = 10, total: Int = 1
    ) -> Data {
        Data(
            "{\"code\":1000,\"data\":{\"list\":[\(list)],\"pagination\":{\"page\":\(page),\"size\":\(size),\"total\":\(total)}}}"
                .utf8)
    }
    @Test func ownedCouponRequestObjectAndStringConditionExactMoney() async throws {
        for stringCondition in [false, true] {
            let text =
                stringCondition
                ? Self.couponJSON.replacingOccurrences(
                    of: "{\"fullAmount\":299.15}", with: "\"{\\\"fullAmount\\\":299.15}\"")
                : Self.couponJSON
            let transport = CouponTransport(data: data(text))
            let service = HTTPUserCouponService(
                environment: .init(baseURL: base), session: session(), transport: transport)
            let result = try await service.loadCoupons(accountID: 1, page: 1, pageSize: 10)
            #expect(result.items.first?.amountYuan == Decimal(string: "30.25"))
            #expect(result.items.first?.minimumSpendYuan == Decimal(string: "299.15"))
            let request = try #require(await transport.requests.first)
            #expect(request.url?.path == "/app/market/coupon/user/page");
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "synthetic-session")
            let body =
                try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
            #expect(body?["page"] as? Int == 1); #expect(body?["size"] as? Int == 10);
            #expect(body?["sort"] as? String == "desc")
        }
    }
    @Test func guestWrongAccountAndDifferentEnvironmentNeverSend() async {
        let transport = CouponTransport(data: data())
        let normal = HTTPUserCouponService(
            environment: .init(baseURL: base), session: session(), transport: transport)
        await #expect(throws: PageReadFailure.authenticationRequired) {
            try await normal.loadCoupons(accountID: 2, page: 1, pageSize: 10)
        }
        let guest = HTTPUserCouponService(
            environment: .init(baseURL: base), session: session(existing: false),
            transport: transport)
        await #expect(throws: PageReadFailure.authenticationRequired) {
            try await guest.loadCoupons(accountID: 1, page: 1, pageSize: 10)
        }
        let wrong = HTTPUserCouponService(
            environment: .init(baseURL: base.appending(path: "other/")), session: session(),
            transport: transport)
        await #expect(throws: PageReadFailure.invalidConfiguration) {
            try await wrong.loadCoupons(accountID: 1, page: 1, pageSize: 10)
        }
        #expect(await transport.requests.isEmpty)
    }
    @Test func logoutSameAccountReloginAndSwitchRejectLateSuccessAndFailure() async throws {
        for change in ["logout", "same", "switch"] {
            for fail in [false, true] {
                let transport = CouponTransport(data: data(), hold: true, fail: fail)
                let loader = CouponAuthLoader()
                let session = SessionCoordinator(
                    loader: loader, storage: CouponAuthStorage(existing: true), environmentURL: base
                )
                let service = HTTPUserCouponService(
                    environment: .init(baseURL: base), session: session, transport: transport)
                let read = Task {
                    try await service.loadCoupons(accountID: 1, page: 1, pageSize: 10)
                }
                await transport.started()
                if change == "logout" {
                    try await session.logout()
                } else {
                    if change == "switch" { await loader.setID(2) }
                    try await session.login(.password(phone: "13800000000", password: "synthetic"))
                }
                await transport.release()
                await #expect(throws: CancellationError.self) { try await read.value }
            }
        }
    }
    @Test func currentErrorsAndCancellationKeepTheirMeaning() async {
        let transport = CouponTransport(data: data(), fail: true)
        let service = HTTPUserCouponService(
            environment: .init(baseURL: base), session: session(), transport: transport)
        await #expect(throws: PageReadFailure.networkUnavailable) {
            try await service.loadCoupons(accountID: 1, page: 1, pageSize: 10)
        }
        let unauthorized = HTTPUserCouponService(
            environment: .init(baseURL: base), session: session(),
            transport: CouponTransport(data: data(), status: 401))
        await #expect(throws: PageReadFailure.authenticationRequired) {
            try await unauthorized.loadCoupons(accountID: 1, page: 1, pageSize: 10)
        }
        let delayed = CouponTransport(data: data(), hold: true)
        let cancellable = HTTPUserCouponService(
            environment: .init(baseURL: base), session: session(), transport: delayed)
        let task = Task { try await cancellable.loadCoupons(accountID: 1, page: 1, pageSize: 10) };
        await delayed.started()
        task.cancel(); await delayed.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func malformedConditionMissingMetadataAndDuplicateIDsFailClosed() async throws {
        let cases = [
            data(
                Self.couponJSON.replacingOccurrences(
                    of: "{\"fullAmount\":299.15}", with: "\"broken\"")),
            data(Self.couponJSON + "," + Self.couponJSON, total: 2),
            data(total: 11), data(page: 2),
            Data("{\"code\":1000,\"data\":{\"list\":[]}}".utf8),
            data(Self.couponJSON.replacingOccurrences(of: "30.25", with: "-1")),
            data(Self.couponJSON.replacingOccurrences(of: "299.15", with: "-1")),
        ]
        for bytes in cases {
            let service = HTTPUserCouponService(
                environment: .init(baseURL: base), session: session(),
                transport: CouponTransport(data: bytes))
            await #expect(throws: PageReadFailure.invalidResponse) {
                try await service.loadCoupons(accountID: 1, page: 1, pageSize: 10)
            }
        }
        let business = HTTPUserCouponService(
            environment: .init(baseURL: base), session: session(),
            transport: CouponTransport(data: Data("{\"code\":1001}".utf8)))
        await #expect(throws: PageReadFailure.businessCode(1001)) {
            try await business.loadCoupons(accountID: 1, page: 1, pageSize: 10)
        }
        let empty = HTTPUserCouponService(
            environment: .init(baseURL: base), session: session(),
            transport: CouponTransport(data: data("", total: 0)))
        #expect(try await empty.loadCoupons(accountID: 1, page: 1, pageSize: 10).items.isEmpty)
    }
    @Test func productsQueryUsesExactYuanMinimumNoAuthorizationOrEligibilityFilter() async throws {
        let bytes = data(
            "{\"id\":7,\"title\":\"商品\",\"price\":4999,\"sold\":3,\"mainPic\":\"https://cdn.invalid/p.png\"}",
            size: 20)
        let transport = CouponTransport(data: bytes)
        let service = HTTPCouponProductsService(
            environment: .init(baseURL: base), transport: transport)
        let result = try await service.loadProducts(
            minimumPriceYuan: Decimal(string: "299.15"), page: 1, pageSize: 20)
        #expect(result.items.first?.priceYuan == 4999)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/app/goods/info/page");
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body =
            try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
        #expect(body?["minPrice"] as? String == "299.15");
        #expect(body?["featured"] as? Bool == false); #expect(body?["recommend"] as? Bool == false)
        #expect(body?["couponId"] == nil); #expect(body?["typeId"] == nil)
        _ = try await service.loadProducts(minimumPriceYuan: nil, page: 1, pageSize: 20)
        let noMinimum = try #require(await transport.requests.last?.httpBody)
        #expect(
            (try JSONSerialization.jsonObject(with: noMinimum) as? [String: Any])?["minPrice"]
                == nil)
        await #expect(throws: PageReadFailure.invalidConfiguration) {
            try await service.loadProducts(minimumPriceYuan: -1, page: 1, pageSize: 20)
        }
        #expect(await transport.requests.count == 2)
    }
    private static let couponJSON =
        "{\"id\":7,\"title\":\"满减券\",\"description\":\"精选商品可用\",\"amount\":30.25,\"type\":0,\"status\":1,\"useStatus\":0,\"condition\":{\"fullAmount\":299.15},\"endTime\":\"2030-01-01T00:00:00\"}"
}
actor CouponTransport: ProductDetailTransport {
    let data: Data; let hold: Bool; let fail: Bool; let status: Int
    var requests: [URLRequest] = []
    var gate: CheckedContinuation<Void, Never>?
    var waiters: [CheckedContinuation<Void, Never>] = []
    init(data: Data, hold: Bool = false, fail: Bool = false, status: Int = 200) {
        self.data = data; self.hold = hold; self.fail = fail; self.status = status
    }
    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if hold {
            await withCheckedContinuation {
                gate = $0; waiters.forEach { $0.resume() }; waiters = []
            }
        }
        if fail { throw URLError(.notConnectedToInternet) }
        let url = try #require(request.url)
        let response = try #require(
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (data, response)
    }
    func started() async {
        if gate != nil { return }; await withCheckedContinuation { waiters.append($0) }
    }
    func release() { gate?.resume(); gate = nil }
}
struct CouponAuthStorage: AccountCredentialStoring {
    let existing: Bool
    func read() -> AccountCredentialRecord? {
        existing
            ? AccountCredentialRecord(
                tokens: AuthenticationTokens(
                    token: "synthetic-session", refreshToken: "synthetic-refresh", expire: 1,
                    refreshExpire: 2),
                profile: AccountProfile(id: 1, nickname: "测试", phone: nil, avatarURL: nil)) : nil
    }
    func save(_ value: AccountCredentialRecord) {}
    func delete() {}
}
actor CouponAuthLoader: AuthenticationLoading {
    var id: Int64 = 1
    func setID(_ value: Int64) { id = value }
    func authenticate(_ credential: LoginCredential) -> AuthenticationTokens {
        AuthenticationTokens(
            token: "synthetic-new", refreshToken: "synthetic-refresh", expire: 1, refreshExpire: 2)
    }
    func profile(token: String) -> AccountProfile {
        AccountProfile(id: id, nickname: "测试", phone: nil, avatarURL: nil)
    }
    func captcha() -> LoginCaptcha { LoginCaptcha(id: "test", imageData: Data([1])) }
    func requestCode(phone: String, captchaID: String, answer: String) -> String { "2468" }
}
