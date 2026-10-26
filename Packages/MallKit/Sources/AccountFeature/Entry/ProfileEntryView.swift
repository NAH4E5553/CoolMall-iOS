import MallCore
import MallImages
import SwiftUI

@MainActor public struct ProfileEntryView: View {
    private let state: AccountState
    private let imagePipeline: MallImagePipeline?
    @State private var model: ProfileViewModel
    @State private var confirmLogout = false
    @State private var unavailable = false
    public init(
        state: AccountState, session: any AccountSession,
        imagePipeline: MallImagePipeline?
    ) {
        self.state = state; self.imagePipeline = imagePipeline;
        _model = State(initialValue: ProfileViewModel(session: session))
    }
    public var body: some View {
        List {
            if let profile = state.profile {
                Section {
                    HStack {
                        Text("头像"); Spacer();
                        AccountAvatar(profile: profile, pipeline: imagePipeline, size: 44)
                    }
                    row("昵称", value: profile.nickname ?? "未设置")
                }
                Section("账号信息") {
                    row("手机号", value: profile.phone ?? "未设置")
                    row("账号", value: String(profile.id))
                }
                Section("社交账号") {
                    row("微信", value: "暂未开放")
                    row("QQ", value: "暂未开放")
                }
                Section("安全") {
                    deferredRow("修改密码")
                    deferredRow("注销账户")
                }
            }
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("profile.error")
                }
            }
            Section {
                Button("退出登录", role: .destructive) { confirmLogout = true }
                    .disabled(model.busy).accessibilityIdentifier("profile.logout")
                if model.busy { ProgressView("正在处理") }
            }
        }
        .navigationTitle("个人中心").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新个人信息").disabled(model.busy || state.profile == nil)
            }
        }
        .confirmationDialog("退出当前账号？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { model.logout() }.accessibilityIdentifier(
                "profile.confirmLogout")
        } message: {
            Text("当前账号的购物车将保留，退出后恢复游客购物车。")
        }
        .modifier(DeferredNotice(isPresented: $unavailable))
        .onDisappear { model.stop() }
    }
    private func deferredRow(_ title: String) -> some View {
        Button {
            unavailable = true
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
        }
    }
    private func row(_ title: String, value: String) -> some View {
        LabeledContent(title) { Text(value).foregroundStyle(.secondary).textSelection(.enabled) }
    }
}
