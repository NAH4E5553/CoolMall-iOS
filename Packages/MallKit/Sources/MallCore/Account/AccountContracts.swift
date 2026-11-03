import Foundation

/// Display-only account identity; credentials never cross the data boundary.
public struct AccountProfile: Equatable, Codable, Sendable {
    public let id: Int64
    public let nickname: String?
    public let phone: String?
    public let avatarURL: URL?
    public init(id: Int64, nickname: String?, phone: String?, avatarURL: URL?) {
        self.id = id; self.nickname = nickname; self.phone = phone; self.avatarURL = avatarURL
    }
}

public enum AccountFailure: Error, Equatable, Sendable {
    case invalidInput, invalidConfiguration, invalidResponse, invalidPayload
    case httpStatus(Int), businessCode(Int), networkUnavailable, timeout
    case credentialRead, credentialWrite, credentialDelete, busy
    case notificationsDenied, notificationDelivery
}

public enum AccountState: Equatable, Sendable {
    case guest
    case signedIn(AccountProfile)
    public var profile: AccountProfile? {
        if case .signedIn(let profile) = self { return profile }; return nil
    }
}

/// Password/code are transient request inputs, never persisted or logged.
public enum LoginCredential: Sendable {
    case password(phone: String, password: String)
    case verificationCode(phone: String, code: String)
}

public struct LoginCaptcha: Equatable, Sendable {
    public let id: String
    public let imageData: Data
    public init(id: String, imageData: Data) { self.id = id; self.imageData = imageData }
}

public protocol AccountSession: Sendable {
    var initialState: AccountState { get }
    func states() async -> AsyncStream<AccountState>
    func login(_ credential: LoginCredential) async throws
    func logout() async throws
    func refreshProfile() async throws
}

public protocol LoginChallenges: Sendable {
    func captcha() async throws -> LoginCaptcha
    func requestCode(phone: String, captchaID: String, answer: String) async throws -> String
}

/// User-initiated local notification channel (PRD-007), not an SMS provider.
public protocol VerificationCodeDelivering: Sendable {
    func prepare() async throws
    func deliver(_ code: String) async throws
}

public enum LoginValidation {
    public static func phone(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 11 && bytes[0] == 49 && (51...57).contains(bytes[1])
            && bytes.allSatisfy { (48...57).contains($0) }
    }
    public static func code(_ value: String) -> Bool {
        value.utf8.count == 4 && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    // Match Kotlin String.length used by the existing Android account validator.
    public static func password(_ value: String) -> Bool { value.utf16.count >= 6 }
    public static func captcha(_ value: String) -> Bool {
        value.utf8.count == 4
            && value.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
            }
    }
}
