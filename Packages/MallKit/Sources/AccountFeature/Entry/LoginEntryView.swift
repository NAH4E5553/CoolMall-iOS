import MallCore
import SwiftUI

/// App routes into this login flow; committed session events decide return navigation.
@MainActor public struct LoginEntryView: View {
    @State private var model: LoginViewModel
    @State private var passwordVisible = false
    @State private var unavailable = false
    @FocusState private var focus: Field?
    private enum Field { case phone, secret, captcha }
    private let onAuthenticated: () -> Void
    private let isActive: Bool
    public init(
        session: any AccountSession, challenges: any LoginChallenges,
        notifier: any VerificationCodeDelivering, isActive: Bool,
        onAuthenticated: @escaping () -> Void
    ) {
        _model = State(
            initialValue: LoginViewModel(
                session: session, challenges: challenges, notifier: notifier))
        self.isActive = isActive; self.onAuthenticated = onAuthenticated
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if model.method == .choice { choice } else { form }
            }
            .padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 32)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(.background)
        .navigationTitle(model.method == .choice ? "登录" : model.method == .code ? "验证码登录" : "密码登录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.method != .choice {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("切换方式") {
                        focus = nil; model.select(.choice)
                    }
                }
            }
            if !model.showsCaptcha {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("完成") { focus = nil }
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { model.showsCaptcha }, set: { if !$0 { model.dismissCaptcha() } })
        ) {
            captchaSheet
        }
        .onChange(of: isActive) { _, active in if !active { model.stop() } }
        .onDisappear { model.stop() }
        .onChange(of: model.completedLogin) { _, complete in if complete { onAuthenticated() } }
        .modifier(DeferredNotice(isPresented: $unavailable))
        .tint(accountAccent)
    }
    private var choice: some View {
        VStack(spacing: 28) {
            Image(systemName: "bag.fill").font(.system(size: 84))
                .symbolRenderingMode(.hierarchical).foregroundStyle(accountAccent)
                .padding(.vertical, 48).accessibilityLabel("青商城")
            Text("欢迎来到青商城").font(.title2.bold())
            AccountPrimaryButton(title: "验证码登录", enabled: true) { model.select(.code) }
                .accessibilityIdentifier("login.chooseCode")
            Button {
                model.select(.password)
            } label: {
                Text("账号密码登录").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(Capsule().stroke(.tertiary, lineWidth: 1))
            }.accessibilityIdentifier("login.choosePassword")
            Text("其他登录方式").font(.footnote).foregroundStyle(.secondary).padding(.top, 24)
            HStack(spacing: 40) {
                ForEach(["微信", "QQ", "支付宝"], id: \.self) { name in
                    Button {
                        unavailable = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle").font(.title)
                            Text(name).font(.caption)
                        }
                    }.foregroundStyle(.secondary)
                }
            }
            LoginAgreement().padding(.top, 24)
        }
    }
    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("你好，\n欢迎登录青商城").font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 20)
            HStack(spacing: 16) {
                Text("+86").foregroundStyle(accountAccent)
                TextField("请输入手机号", text: Binding(get: { model.phone }, set: model.updatePhone))
                    .keyboardType(.phonePad).textContentType(.username)
                    .focused($focus, equals: .phone).accessibilityIdentifier("login.phone")
                    .disabled(model.operation == .login)
            }.padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    Divider().overlay(focus == .phone ? accountAccent : .clear)
                }
            HStack(spacing: 12) {
                if model.method == .code {
                    TextField("验证码", text: $model.code).keyboardType(.numberPad)
                        .textContentType(.oneTimeCode).focused($focus, equals: .secret)
                        .accessibilityIdentifier("login.code")
                    Button(model.operation == .captcha ? "获取中…" : "获取验证码") {
                        focus = nil; model.loadCaptcha()
                    }.disabled(!model.canSend).accessibilityIdentifier("login.requestCode")
                } else {
                    Group {
                        if passwordVisible {
                            TextField("请输入密码", text: $model.password)
                        } else {
                            SecureField("请输入密码", text: $model.password)
                        }
                    }
                    .textContentType(.password).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().focused($focus, equals: .secret)
                    .accessibilityIdentifier("login.password")
                    Button {
                        passwordVisible.toggle()
                    } label: {
                        Image(systemName: passwordVisible ? "eye.slash" : "eye")
                            .frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel(passwordVisible ? "隐藏密码" : "显示密码")
                }
            }
            .disabled(model.operation == .login)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Divider().overlay(focus == .secret ? accountAccent : .clear)
            }
            LoginAgreement()
            if let error = model.error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("login.error")
            }
            if let notice = model.notice {
                Text(notice).foregroundStyle(.secondary).accessibilityIdentifier("login.notice")
            }
            AccountPrimaryButton(
                title: "登录", enabled: model.canLogin, busy: model.operation == .login
            ) {
                focus = nil; model.login()
            }.accessibilityIdentifier("login.submit")
            HStack {
                Spacer()
                if model.method == .password {
                    Button("去注册") { unavailable = true }
                    Text("｜").foregroundStyle(.tertiary)
                    Button("忘记密码") { unavailable = true }
                } else {
                    Button("使用密码登录") {
                        focus = nil; model.select(.password)
                    }
                }
                Spacer()
            }.font(.subheadline).padding(.top, 16)
        }
    }
    private var captchaSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            captchaInput; captchaPicture
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            captchaPicture; captchaInput
                        }
                    }
                    if model.operation == .captcha { ProgressView("正在获取图形验证码") }
                    if let error = model.captchaError {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier(
                            "login.captcha.error")
                        Button("重新获取") { model.loadCaptcha() }.disabled(model.busy)
                    }
                    AccountPrimaryButton(
                        title: "完成验证", enabled: model.canConfirmCaptcha,
                        busy: model.operation == .sendingCode
                    ) {
                        focus = nil; model.sendCode()
                    }.accessibilityIdentifier("login.captcha.confirm")
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("安全验证").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private var captchaInput: some View {
        TextField("请输入图形验证码", text: $model.imageAnswer)
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .textFieldStyle(.roundedBorder).focused($focus, equals: .captcha)
            .disabled(model.busy).accessibilityIdentifier("login.captcha.answer")
    }
    @ViewBuilder private var captchaPicture: some View {
        if let captcha = model.captcha {
            Button {
                model.loadCaptcha()
            } label: {
                CaptchaImage(data: captcha.imageData)
            }
            .disabled(model.busy).accessibilityLabel("刷新图形验证码")
        }
    }
}
