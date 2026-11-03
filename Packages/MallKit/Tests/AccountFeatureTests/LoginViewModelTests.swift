import Foundation
import MallCore
import Testing
@testable import AccountFeature

@MainActor struct LoginViewModelTests {
    @Test func validatesBothFormsWithoutSubmission() async {
        let fake = LoginFake()
        let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
        vm.select(.password); vm.updatePhone("13800000000"); vm.password = "12345"
        #expect(!vm.canLogin)
        vm.password = "123456"; #expect(vm.canLogin)
        vm.password = "🔑🔑🔑"; #expect(vm.canLogin)
        vm.password = "🔑🔑"; #expect(!vm.canLogin)
        vm.select(.code); #expect(vm.password.isEmpty)
        vm.code = "１２３４"; #expect(!vm.canLogin)
        vm.code = "2468"; #expect(vm.canLogin)
        #expect(await fake.logins == 0)
    }
    @Test func successfulLoginIsSingleFlightAndClearsSecrets() async {
        let fake = LoginFake()
        let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
        vm.select(.password); vm.updatePhone("13800000000"); vm.password = "123456"
        vm.login(); vm.login()
        await settle(vm)
        #expect(await fake.logins == 1)
        #expect(vm.completedLogin && vm.password.isEmpty && vm.error == nil)
    }
    @Test func permissionDenialMakesNoCaptchaRequest() async {
        let fake = LoginFake(denied: true)
        let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
        vm.select(.code); vm.updatePhone("13800000000"); vm.loadCaptcha()
        await settle(vm)
        #expect(await fake.captchas == 0)
        #expect(vm.captchaError?.contains("系统设置") == true)
        #expect(vm.canSend)
    }
    @Test func challengeThenCodeUsesCapturedIdentityAndClearsSheet() async {
        let fake = LoginFake()
        let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
        vm.select(.code); vm.updatePhone("13800000000"); vm.loadCaptcha()
        await settle(vm)
        vm.imageAnswer = "1234"; vm.sendCode(); vm.sendCode()
        await settle(vm)
        #expect(await fake.sent == 1)
        #expect(await fake.delivered == 1)
        #expect(!vm.showsCaptcha && vm.captcha == nil && vm.notice != nil)
        #expect(vm.code.isEmpty)
    }
    @Test func changedPhoneRejectsUncooperativeLateCaptcha() async {
        let fake = LoginFake(holdsCaptcha: true)
        let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
        vm.select(.code); vm.updatePhone("13800000000"); vm.loadCaptcha()
        await fake.waitForCaptcha()
        vm.updatePhone("13900000000")
        await fake.releaseCaptcha()
        for _ in 0..<50 { await Task.yield() }
        #expect(!vm.showsCaptcha && vm.captcha == nil && !vm.busy)
        #expect(vm.phone == "13900000000")
    }
    @Test func dismissedChallengeRejectsLateResult() async {
        let fake = LoginFake(holdsCaptcha: true)
        let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
        vm.select(.code); vm.updatePhone("13800000000"); vm.loadCaptcha()
        await fake.waitForCaptcha(); vm.dismissCaptcha(); await fake.releaseCaptcha()
        for _ in 0..<50 { await Task.yield() }
        #expect(!vm.showsCaptcha && vm.captcha == nil && vm.captchaError == nil)
    }
    @Test func captchaSubmissionRejectionUsesSpecificCopyAndCanRetry() async {
        let fake = LoginFake(requestFailure: .businessCode(9999))
        let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
        vm.select(.code); vm.updatePhone("13800000000"); vm.loadCaptcha()
        await settle(vm); vm.imageAnswer = "1234"; vm.sendCode(); await settle(vm)
        #expect(vm.captchaError == "图形验证码输入错误！")
        #expect(vm.showsCaptcha && vm.canConfirmCaptcha && vm.imageAnswer == "1234")
        #expect(await fake.delivered == 0)
        await fake.setRequestFailure(nil); vm.sendCode(); await settle(vm)
        #expect(vm.captchaError == nil && !vm.showsCaptcha && vm.notice != nil)
        #expect(await fake.sent == 2)
        #expect(await fake.delivered == 1)
    }
    @Test func captchaTransportFailuresKeepTheirOwnMessages() async {
        let cases: [(AccountFailure, String)] = [
            (.networkUnavailable, "网络连接失败，请检查网络后重试。"),
            (.timeout, "请求超时，请重试。"),
        ]
        for (failure, message) in cases {
            let fake = LoginFake(requestFailure: failure)
            let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
            vm.select(.code); vm.updatePhone("13800000000"); vm.loadCaptcha()
            await settle(vm); vm.imageAnswer = "1234"; vm.sendCode(); await settle(vm)
            #expect(vm.captchaError == message && vm.showsCaptcha && vm.canConfirmCaptcha)
            #expect(await fake.delivered == 0)
        }
    }
    @Test func captchaFetchRejectionDoesNotClaimAnIncorrectAnswer() async {
        let fake = LoginFake(captchaFailure: .businessCode(9999))
        let vm = LoginViewModel(session: fake, challenges: fake, notifier: fake)
        vm.select(.code); vm.updatePhone("13800000000"); vm.loadCaptcha(); await settle(vm)
        #expect(vm.captchaError == "服务器未接受本次操作，请检查输入后重试。")
        #expect(vm.showsCaptcha && vm.captcha == nil && !vm.canConfirmCaptcha)
        #expect(await fake.sent == 0)
        #expect(await fake.delivered == 0)
    }
    private func settle(_ vm: LoginViewModel) async {
        for _ in 0..<2000 { if !vm.busy { return }; await Task.yield() }
        Issue.record("Action did not settle")
    }
}

private actor LoginFake: AccountSession, LoginChallenges, VerificationCodeDelivering {
    nonisolated let initialState: AccountState = .guest
    let denied: Bool
    let holdsCaptcha: Bool
    let captchaFailure: AccountFailure?
    var requestFailure: AccountFailure?
    var logins = 0; var captchas = 0; var sent = 0; var delivered = 0
    var gate: CheckedContinuation<Void, Never>?
    var started: [CheckedContinuation<Void, Never>] = []
    init(
        denied: Bool = false, holdsCaptcha: Bool = false,
        requestFailure: AccountFailure? = nil, captchaFailure: AccountFailure? = nil
    ) {
        self.denied = denied; self.holdsCaptcha = holdsCaptcha
        self.requestFailure = requestFailure; self.captchaFailure = captchaFailure
    }
    func setRequestFailure(_ value: AccountFailure?) { requestFailure = value }
    func states() -> AsyncStream<AccountState> {
        AsyncStream {
            $0.yield(.guest); $0.finish()
        }
    }
    func login(_ credential: LoginCredential) { logins += 1 }
    func logout() {}
    func refreshProfile() {}
    func prepare() throws { if denied { throw AccountFailure.notificationsDenied } }
    func deliver(_ code: String) { delivered += 1 }
    func captcha() async throws -> LoginCaptcha {
        captchas += 1
        if let captchaFailure { throw captchaFailure }
        if holdsCaptcha {
            await withCheckedContinuation { continuation in
                gate = continuation; started.forEach { $0.resume() }; started = []
            }
        }
        return .init(id: "challenge", imageData: Data([1]))
    }
    func waitForCaptcha() async {
        if gate != nil { return }
        await withCheckedContinuation { started.append($0) }
    }
    func releaseCaptcha() { gate?.resume(); gate = nil }
    func requestCode(phone: String, captchaID: String, answer: String) throws -> String {
        #expect(phone == "13800000000" && captchaID == "challenge" && answer == "1234")
        sent += 1
        if let requestFailure { throw requestFailure }
        return "2468"
    }
}
