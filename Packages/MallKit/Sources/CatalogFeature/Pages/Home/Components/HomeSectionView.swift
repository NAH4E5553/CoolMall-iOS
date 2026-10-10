import SwiftUI

/// HOME-02 home-specific section skeleton: a semantic title plus the card's
/// read-only engineering placeholder. Fills the available content width and
/// stays left-aligned; Dynamic Type wraps instead of shrinking or clipping.
/// The placeholder is plain text — not a button, no cards, no images.
struct HomeSectionView: View {
    let title: String
    let pendingText: String
    let titleAccessibilityID: String
    let pendingAccessibilityID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityIdentifier(titleAccessibilityID)
            Text(pendingText)
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(pendingAccessibilityID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview("标题与占位") {
        HomeSectionView(
            title: "推荐商品",
            pendingText: "推荐商品内容待接入",
            titleAccessibilityID: "preview.section.title",
            pendingAccessibilityID: "preview.section.pending"
        )
        .padding(.horizontal, 16)
    }

    #Preview("长文字与特大字体") {
        HomeSectionView(
            title: "推荐商品长标题用于特大字体换行验证",
            pendingText: "推荐商品内容待接入——长占位文字，验证 body 字号下的换行与左对齐，不缩字、不截断。",
            titleAccessibilityID: "preview.section.title",
            pendingAccessibilityID: "preview.section.pending"
        )
        .padding(.horizontal, 16)
        .dynamicTypeSize(.accessibility5)
    }

    #Preview("深色") {
        HomeSectionView(
            title: "限时精选",
            pendingText: "限时精选内容待接入",
            titleAccessibilityID: "preview.section.title",
            pendingAccessibilityID: "preview.section.pending"
        )
        .padding(.horizontal, 16)
        .preferredColorScheme(.dark)
    }
#endif
