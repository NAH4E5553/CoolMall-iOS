import SwiftUI

/// Non-business presentation reused by the two F0 entry screens.
public struct FixtureNoticeView: View {
    private let title: String
    private let detail: String
    public init(title: String, detail: String) { self.title = title; self.detail = detail }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(detail).font(.body).foregroundStyle(.secondary)
        }.padding()
    }
}

#Preview("Long text / dark") {
    FixtureNoticeView(title: "工程基线", detail: "本页面使用本地夹具，用于验证模块组装与系统导航。")
        .environment(\.dynamicTypeSize, .accessibility3).preferredColorScheme(.dark)
}
