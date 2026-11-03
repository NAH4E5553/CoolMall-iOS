import SwiftUI

/// Page-specific brand styling; no business state or service lookup.
enum SearchStyle {
    static let accent = Color(red: 0.30, green: 0.34, blue: 1)
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.075) : Color(red: 0.94, green: 0.95, blue: 0.98)
    }
}
struct SearchBarView: View {
    @Binding var text: String
    var busy: Bool
    var focused: FocusState<Bool>.Binding
    let editingRevision: UInt64
    let submit: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(
                true)
            TextField("输入内容进行搜索", text: $text)
                .font(.subheadline).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused(focused).accessibilityIdentifier("search.input")
                .id(editingRevision)
                .onSubmit { submit() }
            Button(action: submit) {
                Text(busy ? "搜索中" : "搜索").font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(SearchStyle.accent, in: Capsule())
            }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("search.submit")
        }.padding(5).padding(.leading, 8).frame(minHeight: 44)
            .background(.quinary, in: Capsule())
    }

}
struct SearchToastView: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.white).padding(12)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .padding().accessibilityIdentifier("search.toast").allowsHitTesting(false)
    }
}
