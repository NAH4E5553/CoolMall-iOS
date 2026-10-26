import Foundation
import MallCore
import Observation

@MainActor @Observable
final class LoginViewModel {
    enum Method { case choice, code, password }
    enum Operation { case idle, captcha, sendingCode, login }
    private(set) var completedLogin = false
    private(set) var method: Method = .choice
    private(set) var phone = ""
    var password = ""
    var code = ""
    var imageAnswer = ""
    private(set) var operation: Operation = .idle
    private(set) var captcha: LoginCaptcha?
    private(set) var showsCaptcha = false
    private(set) var error: String?
    private(set) var captchaError: String?
    private(set) var notice: String?
    private let session: any AccountSession
    private let challenges: any LoginChallenges
    private let notifier: any VerificationCodeDelivering
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    var busy: Bool { operation != .idle }
    var canLogin: Bool {
        !busy && LoginValidation.phone(phone)
            && (method == .password
                ? LoginValidation.password(password) : LoginValidation.code(code))
    }
    var canSend: Bool { !busy && LoginValidation.phone(phone) }
    var canConfirmCaptcha: Bool {
        !busy && captcha != nil && LoginValidation.captcha(imageAnswer)
    }
    init(
        session: any AccountSession, challenges: any LoginChallenges,
        notifier: any VerificationCodeDelivering
    ) {
        self.session = session; self.challenges = challenges; self.notifier = notifier
    }
    func select(_ method: Method) {
        stop(); self.method = method; password = ""; code = ""; error = nil; notice = nil
    }
    func updatePhone(_ value: String) {
        guard value != phone else { return }
        stop(); phone = value; code = ""; error = nil; notice = nil
    }
    func stop() {
        generation &+= 1; task?.cancel(); task = nil; operation = .idle
        showsCaptcha = false; captcha = nil; imageAnswer = ""; captchaError = nil
    }
    func dismissCaptcha() { stop() }
    func loadCaptcha() {
        guard canSend else { return }
        generation &+= 1
        let epoch = generation
        operation = .captcha; error = nil; captchaError = nil; notice = nil
        captcha = nil; imageAnswer = ""; showsCaptcha = true
        task = Task {
            do {
                try await notifier.prepare()
                try check(epoch)
                let value = try await challenges.captcha()
                try check(epoch)
                captcha = value; operation = .idle
            } catch {
                guard generation == epoch, !Task.isCancelled else { return }
                operation = .idle
                if !(error is CancellationError) { captchaError = accountMessage(error) }
            }
        }
    }
    func sendCode() {
        guard canConfirmCaptcha, let captcha else { return }
        generation &+= 1
        let epoch = generation
        let capturedPhone = phone; let answer = imageAnswer
        operation = .sendingCode; captchaError = nil
        task = Task {
            do {
                // Check current system permission before creating a code on the server.
                try await notifier.prepare(); try check(epoch)
                let value = try await challenges.requestCode(
                    phone: capturedPhone, captchaID: captcha.id, answer: answer)
                try check(epoch)
                try await notifier.deliver(value)
                try check(epoch)
                operation = .idle; showsCaptcha = false; self.captcha = nil; imageAnswer = ""
                notice = "验证码已通过本地通知发送，请查看通知。"
            } catch {
                guard generation == epoch, !Task.isCancelled else { return }
                operation = .idle
                if !(error is CancellationError) {
                    if let failure = error as? AccountFailure, case .businessCode = failure {
                        captchaError = "图形验证码输入错误！"
                    } else {
                        captchaError = accountMessage(error)
                    }
                }
            }
        }
    }
    func login() {
        guard canLogin else { return }
        generation &+= 1
        let epoch = generation
        let credential: LoginCredential =
            method == .password
            ? .password(phone: phone, password: password)
            : .verificationCode(phone: phone, code: code)
        operation = .login; error = nil; notice = nil
        task = Task {
            do {
                try await session.login(credential)
                try check(epoch)
                password = ""; code = ""; operation = .idle; completedLogin = true
                // App observes the committed identity and performs the navigation.
            } catch {
                guard generation == epoch, !Task.isCancelled else { return }
                operation = .idle
                if !(error is CancellationError) { self.error = accountMessage(error) }
            }
        }
    }
    private func check(_ epoch: UInt64) throws {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
    }
}

func accountMessage(_ error: any Error) -> String {
    guard let failure = error as? AccountFailure else { return "操作失败，请重试。" }
    switch failure {
    case .invalidInput: return "请检查手机号、密码或验证码。"
    case .notificationsDenied: return "请在系统设置中允许青商城通知后重试，或使用密码登录。"
    case .notificationDelivery: return "验证码通知发送失败，请重试。"
    case .credentialRead: return "无法读取登录信息，请重试登录或退出当前会话。"
    case .credentialWrite: return "登录信息保存失败，请重试。"
    case .credentialDelete: return "退出失败，登录信息尚未清除，请重试。"
    case .httpStatus(401): return "登录状态已失效，请重新登录。"
    case .businessCode: return "服务器未接受本次操作，请检查输入后重试。"
    case .networkUnavailable: return "网络连接失败，请检查网络后重试。"
    case .timeout: return "请求超时，请重试。"
    case .busy: return "正在处理，请稍后重试。"
    case .invalidConfiguration, .invalidResponse, .invalidPayload, .httpStatus:
        return "暂时无法完成操作，请稍后重试。"
    }
}
