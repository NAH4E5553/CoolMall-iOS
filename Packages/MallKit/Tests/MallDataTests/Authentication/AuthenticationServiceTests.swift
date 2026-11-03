import Foundation
import MallCore
import Testing
@testable import MallData

struct AuthenticationServiceTests {
    private let environment = APIEnvironment(baseURL: URL(string: "https://example.invalid/app/")!)
    @Test func passwordRequestAndTokenFields() async throws {
        let transport = AuthTransport(
            body:
                #"{"code":1000,"data":{"token":"test-access","refreshToken":"test-refresh","expire":60,"refreshExpire":120}}"#
        )
        let service = HTTPAuthenticationService(environment: environment, transport: transport)
        let value = try await service.authenticate(
            .password(phone: "13800000000", password: "test-only"))
        #expect(value.token == "test-access")
        let request = try #require(await transport.last)
        #expect(request.url?.absoluteString == "https://example.invalid/app/user/login/password")
        #expect(
            request.httpMethod == "POST"
                && request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(
            JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
        #expect(body == ["phone": "13800000000", "password": "test-only"])
    }
    @Test func codeRequestAndLoginUseDistinctWireKeys() async throws {
        let transport = AuthTransport(body: #"{"code":1000,"data":"2468"}"#)
        let service = HTTPAuthenticationService(environment: environment, transport: transport)
        let code = try await service.requestCode(
            phone: "13800000000", captchaID: "challenge", answer: "1234")
        #expect(code == "2468")
        let request = try #require(await transport.last)
        #expect(request.url?.path == "/app/user/login/smsCode")
        let body = try #require(
            JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
        #expect(body == ["phone": "13800000000", "captchaId": "challenge", "code": "1234"])
        await transport.setBody(
            #"{"code":1000,"data":{"token":"a","refreshToken":"r","expire":1,"refreshExpire":2}}"#)
        _ = try await service.authenticate(.verificationCode(phone: "13800000000", code: "2468"))
        let login = try #require(await transport.last)
        let loginBody = try #require(
            JSONSerialization.jsonObject(with: login.httpBody!) as? [String: String])
        #expect(login.url?.path == "/app/user/login/phone")
        #expect(loginBody == ["phone": "13800000000", "smsCode": "2468"])
    }
    @Test func profileUsesRawAuthorizationAndIgnoresUnconsumedPassword() async throws {
        let transport = AuthTransport(
            body:
                #"{"code":1000,"data":{"id":12,"nickName":"用户","phone":null,"avatarUrl":"javascript:bad","password":{"ignored":true}}}"#
        )
        let service = HTTPAuthenticationService(environment: environment, transport: transport)
        let profile = try await service.profile(token: "synthetic-token")
        #expect(profile.id == 12 && profile.avatarURL == nil)
        #expect(
            await transport.last?.value(forHTTPHeaderField: "Authorization") == "synthetic-token")
    }
    @Test func statusBusinessAndPayloadFailuresStayDistinct() async throws {
        let transport = AuthTransport(body: "broken", status: 503)
        let service = HTTPAuthenticationService(environment: environment, transport: transport)
        await #expect(throws: AccountFailure.httpStatus(503)) { try await service.captcha() }
        await transport.setBody(#"{"code":9001,"data":false}"#, status: 200)
        await #expect(throws: AccountFailure.businessCode(9001)) { try await service.captcha() }
        await transport.setBody(#"{"code":1000,"data":{}}"#)
        await #expect(throws: AccountFailure.invalidPayload) { try await service.captcha() }
        #expect(await transport.calls == 3)
    }
    @Test func captchaAcceptsBoundedBase64AndInvalidInputNeverSends() async throws {
        let transport = AuthTransport(
            body: #"{"code":1000,"data":{"captchaId":"c1","data":"data:image/png;base64,AQID"}}"#)
        let service = HTTPAuthenticationService(environment: environment, transport: transport)
        #expect(try await service.captcha().imageData == Data([1, 2, 3]))
        await #expect(throws: AccountFailure.invalidInput) {
            try await service.requestCode(phone: "bad", captchaID: "c1", answer: "1234")
        }
        #expect(await transport.calls == 1)
    }
}

private actor AuthTransport: ProductDetailTransport {
    var body: String; var status: Int
    var last: URLRequest?; var calls = 0
    init(body: String, status: Int = 200) { self.body = body; self.status = status }
    func setBody(_ value: String, status: Int = 200) { body = value; self.status = status }
    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        last = request; calls += 1
        return (
            Data(body.utf8),
            HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}
