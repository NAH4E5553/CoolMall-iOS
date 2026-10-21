import SwiftUI

struct HomeSectionView<Content: View>: View {
    let title: String?
    let key: String
    var action: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline).accessibilityIdentifier("home.section.\(key).title")
                    Spacer()
                    if let action {
                        Button("查看全部", action: action).font(.subheadline)
                            .accessibilityIdentifier("home.section.\(key).all")
                    }
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
