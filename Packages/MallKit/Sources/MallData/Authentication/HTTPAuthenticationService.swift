import Foundation
import MallCore

struct AuthenticationTokens: Codable, Sendable {
    let token: String
    let refreshToken: String
    // Preserve wire values without inventing an expiry unit/automatic renewal policy.
    let expire: Int64
    let refreshExpire: Int64
}

protocol AuthenticationLoading: LoginChallenges {
    func authenticate(_ credential: LoginCredential) async throws -> AuthenticationTokens
    func profile(token: String) async throws -> AccountProfile
}

/// Exact Android AuthService endpoints; no automatic replay of login/code requests.
final class HTTPAuthenticationService: AuthenticationLoading, Sendable {
    private let environment: APIEnvironment
    private let transport: any ProductDetailTransport
    init(environment: APIEnvironment, transport: any ProductDetailTransport) {
        self.environment = environment; self.transport = transport
    }
    convenience init(environment: APIEnvironment) {
        #if DEBUG
            if environment.baseURL.host?.hasSuffix(".account-keychain.invalid") == true,
                ProcessInfo.processInfo.arguments.contains("--ui-account-keychain")
            {
                let configuration = URLSessionTransport.makeProductionConfiguration(
                    resourceTimeout: environment.resourceTimeout)
                configuration.protocolClasses = [AccountKeychainUITestProtocol.self]
                self.init(
                    environment: environment,
                    transport: URLSessionTransport(
                        session: URLSession(configuration: configuration)))
                return
            }
        #endif
        self.init(
            environment: environment,
            transport: URLSessionTransport(resourceTimeout: environment.resourceTimeout))
    }

    func authenticate(_ credential: LoginCredential) async throws -> AuthenticationTokens {
        let path: String
        let body: Data
        switch credential {
        case .password(let phone, let password):
            guard LoginValidation.phone(phone), LoginValidation.password(password) else {
                throw AccountFailure.invalidInput
            }
            struct Input: Encodable { let phone: String; let password: String }
            path = "user/login/password"
            body = try JSONEncoder().encode(Input(phone: phone, password: password))
        case .verificationCode(let phone, let code):
            guard LoginValidation.phone(phone), LoginValidation.code(code) else {
                throw AccountFailure.invalidInput
            }
            struct Input: Encodable { let phone: String; let smsCode: String }
            path = "user/login/phone"
            body = try JSONEncoder().encode(Input(phone: phone, smsCode: code))
        }
        let result: AuthenticationTokens = try await read(path, body: body)
        guard !result.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !result.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            result.expire > 0, result.refreshExpire > 0
        else { throw AccountFailure.invalidPayload }
        return result
    }

    func captcha() async throws -> LoginCaptcha {
        struct Payload: Decodable { let captchaId: String; let data: String }
        let payload: Payload = try await read("user/login/captcha")
        let raw: String
        if payload.data.hasPrefix("data:image/"), let comma = payload.data.firstIndex(of: ",") {
            guard payload.data[..<comma].hasSuffix(";base64") else {
                throw AccountFailure.invalidPayload
            }
            raw = String(payload.data[payload.data.index(after: comma)...])
        } else {
            raw = payload.data
        }
        guard !payload.captchaId.isEmpty, raw.count < 2_800_000,
            let bytes = Data(base64Encoded: raw), !bytes.isEmpty
        else {
            throw AccountFailure.invalidPayload
        }
        return LoginCaptcha(id: payload.captchaId, imageData: bytes)
    }

    func requestCode(phone: String, captchaID: String, answer: String) async throws -> String {
        guard LoginValidation.phone(phone), !captchaID.isEmpty, LoginValidation.captcha(answer)
        else {
            throw AccountFailure.invalidInput
        }
        struct Input: Encodable { let phone: String; let captchaId: String; let code: String }
        let code: String = try await read(
            "user/login/smsCode",
            body: JSONEncoder().encode(
                Input(phone: phone, captchaId: captchaID, code: answer)))
        guard LoginValidation.code(code) else { throw AccountFailure.invalidPayload }
        return code
    }

    func profile(token: String) async throws -> AccountProfile {
        struct Payload: Decodable {
            let id: Int64; let nickName: String?; let phone: String?; let avatarUrl: String?
        }
        let payload: Payload = try await read("user/info/person", token: token)
        guard payload.id > 0 else { throw AccountFailure.invalidPayload }
        let avatar = payload.avatarUrl.flatMap(URL.init(string:)).flatMap {
            ($0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil)
                ? $0 : nil
        }
        return AccountProfile(
            id: payload.id, nickname: payload.nickName,
            phone: payload.phone, avatarURL: avatar)
    }

    private func read<T: Decodable & Sendable>(
        _ path: String, body: Data? = nil, token: String? = nil
    ) async throws -> T {
        let base = environment.baseURL
        guard base.scheme == "https", base.host?.isEmpty == false,
            base.absoluteString.hasSuffix("/"), base.query == nil, base.fragment == nil,
            base.user == nil, base.password == nil,
            environment.requestTimeout > 0, environment.requestTimeout.isFinite,
            environment.resourceTimeout > 0, environment.resourceTimeout.isFinite,
            let url = URL(string: path, relativeTo: base)?.absoluteURL
        else {
            throw AccountFailure.invalidConfiguration
        }
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: environment.requestTimeout)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        let data = try await APIClient.authenticationBodyData(request, transport: transport)
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(AuthenticationHeader.self, from: data)
            guard header.code == 1000 else { throw AccountFailure.businessCode(header.code) }
            return try decoder.decode(AuthenticationEnvelope<T>.self, from: data).data
        } catch let failure as AccountFailure { throw failure } catch {
            throw AccountFailure.invalidPayload
        }
    }
}

private struct AuthenticationEnvelope<Value: Decodable>: Decodable { let data: Value }

extension APIClient {
    static func authenticationBodyData(_ request: URLRequest, transport: any ProductDetailTransport)
        async throws -> Data
    {
        do {
            try Task.checkCancellation()
            let (data, response) = try await transport.send(request: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw AccountFailure.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw AccountFailure.httpStatus(http.statusCode)
            }
            return data
        } catch let error as AccountFailure { throw error } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut
                ? AccountFailure.timeout : AccountFailure.networkUnavailable
        } catch { throw AccountFailure.networkUnavailable }
    }
}

private struct AuthenticationHeader: Decodable { let code: Int }

#if DEBUG
    /// Synthetic HTTP only; SessionCoordinator and Keychain remain production adapters.
    private final class AccountKeychainUITestProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host?.hasSuffix(".account-keychain.invalid") == true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let body: String
            switch request.url?.lastPathComponent {
            case "phone", "password":
                body =
                    #"{"code":1000,"data":{"token":"synthetic-keychain-access","refreshToken":"synthetic-keychain-refresh","expire":60,"refreshExpire":120}}"#
            case "person":
                guard
                    request.value(forHTTPHeaderField: "Authorization")
                        == "synthetic-keychain-access"
                else {
                    client?.urlProtocol(
                        self, didFailWithError: URLError(.userAuthenticationRequired));
                    return
                }
                body =
                    #"{"code":1000,"data":{"id":920002,"nickName":"Keychain测试用户","phone":"13800000000"}}"#
            default:
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
            }
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
#endif
