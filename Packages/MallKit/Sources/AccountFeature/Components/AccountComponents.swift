import MallCore
import MallImages
import SwiftUI

let accountAccent = Color(red: 0.30, green: 0.34, blue: 1.0)

struct AccountAvatar: View {
    let profile: AccountProfile?
    let pipeline: MallImagePipeline?
    var size: CGFloat = 68
    var body: some View {
        Group {
            if let url = profile?.avatarURL, let pipeline {
                RemoteImage(
                    url: url, targetSize: CGSize(width: size, height: size), pipeline: pipeline)
            } else {
                Circle().fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill").font(.system(size: size * 0.44))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct AccountPrimaryButton: View {
    let title: String
    let enabled: Bool
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(.white) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(accountAccent.opacity(enabled ? 1 : 0.45), in: Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

struct DeferredNotice: ViewModifier {
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content.alert("暂未开放", isPresented: $isPresented) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("此功能暂未开放。")
        }
    }
}

struct LoginAgreement: View {
    @State private var unavailable = false
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) { terms }
            VStack(alignment: .leading, spacing: 4) { terms }
        }
        .font(.footnote).foregroundStyle(.secondary)
        .alert("协议内容暂未提供", isPresented: $unavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("用户协议和隐私政策的正式内容暂未接入。")
        }
    }
    @ViewBuilder private var terms: some View {
        Text("登录前请阅读")
        Button("《用户协议》") { unavailable = true }.tint(accountAccent)
        Text("和")
        Button("《隐私政策》") { unavailable = true }.tint(accountAccent)
    }
}
