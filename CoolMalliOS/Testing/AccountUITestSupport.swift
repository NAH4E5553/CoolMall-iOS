#if DEBUG
    import Foundation
    import MallCore

    /// Explicit offline scenarios; invalid flags cannot silently reach production auth.
    actor AccountUITestSupport: AccountSession, LoginChallenges, VerificationCodeDelivering {
        nonisolated let initialState: AccountState
        private let scenario: String
        private var state: AccountState = .guest
        private var observers: [UUID: AsyncStream<AccountState>.Continuation] = [:]
        init(scenario: String, signedIn: Bool = false) {
            self.scenario = scenario
            initialState =
                signedIn
                ? .signedIn(
                    AccountProfile(
                        id: 920001, nickname: "测试用户", phone: "13800000000", avatarURL: nil))
                : .guest
            state = initialState
        }
        nonisolated static func make(arguments: [String]) -> AccountUITestSupport? {
            guard let index = arguments.firstIndex(of: "--ui-account-fixture") else {
                // Existing offline cart tests must not depend on device credentials.
                return arguments.contains("--ui-cart-store")
                    ? AccountUITestSupport(scenario: "guestOnly") : nil
            }
            let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : "invalid"
            return AccountUITestSupport(
                scenario: value,
                signedIn: arguments.contains("--ui-orders")
                    && arguments.contains("--ui-orders-signed-in"))
        }
        func states() -> AsyncStream<AccountState> {
            let id = UUID()
            let (stream, continuation) = AsyncStream<AccountState>.makeStream(
                bufferingPolicy: .bufferingNewest(1))
            observers[id] = continuation; continuation.yield(state)
            continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
            return stream
        }
        private func remove(_ id: UUID) { observers[id] = nil }
        func login(_ credential: LoginCredential) async throws {
            try Task.checkCancellation()
            guard
                ["success", "passwordFailure", "captchaFailure", "notificationDenied", "pending"]
                    .contains(scenario)
            else {
                throw AccountFailure.invalidConfiguration
            }
            if scenario == "pending" { try await Task.sleep(for: .seconds(100)) }
            if scenario == "passwordFailure" { throw AccountFailure.businessCode(9999) }
            let phone: String
            switch credential {
            case .password(let input, let secret):
                guard LoginValidation.phone(input), LoginValidation.password(secret) else {
                    throw AccountFailure.invalidInput
                }
                phone = input
            case .verificationCode(let input, let code):
                guard LoginValidation.phone(input), code == "2468" else {
                    throw AccountFailure.invalidInput
                }
                phone = input
            }
            try Task.checkCancellation()
            state = .signedIn(
                AccountProfile(id: 920001, nickname: "测试用户", phone: phone, avatarURL: nil))
            for item in observers.values { item.yield(state) }
        }
        func logout() { state = .guest; for item in observers.values { item.yield(state) } }
        func refreshProfile() {}
        func prepare() throws {
            if scenario == "notificationDenied" { throw AccountFailure.notificationsDenied }
        }
        func deliver(_ code: String) throws { try prepare() }
        func captcha() throws -> LoginCaptcha {
            if scenario == "captchaFailure" { throw AccountFailure.networkUnavailable }
            guard
                let bytes = Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAHgAAAAwCAIAAABVDSmEAAAA10lEQVR4nO3WOw7CMABEQQ5Gw8W5GrQIQZSP/UAwK5fRrj1VTjdJcvr0Bf4loKOAjgI6CugooKOAjgI6ylro8+X6ePaNPZUsn+/pHPIx6KOPBQ0a9KjtlSWgj26vLAF9dHtIZiyu7AQddYKOOkFHnaCjTtBR549DD5l4KtnXuVyybwL05hLQL0pAz5oAHU2AjiZAR539IuhoEXS0CDpaBB0tgo4Wj0K/+315efbdacjEjHtuCmjQoGc/AHT0ANDRA0DL9ICOAjoK6Cigo4COAjoK6Cigo9wBEmKgyrBfgYwAAAAASUVORK5CYII="
                )
            else { throw AccountFailure.invalidPayload }
            return LoginCaptcha(id: "synthetic-captcha", imageData: bytes)
        }
        func requestCode(phone: String, captchaID: String, answer: String) throws -> String {
            guard captchaID == "synthetic-captcha", LoginValidation.phone(phone) else {
                throw AccountFailure.invalidInput
            }
            guard answer == "1234" else { throw AccountFailure.businessCode(9999) }
            return "2468"
        }
    }
#endif
