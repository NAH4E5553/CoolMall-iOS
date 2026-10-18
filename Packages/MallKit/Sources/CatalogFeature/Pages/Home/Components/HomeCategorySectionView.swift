import MallCore
import MallImages
import SwiftUI

struct HomeCategorySectionView: View {
    let categories: [HomeCategory]
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HomeSectionView(title: nil, key: "category") {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: typeSize.isAccessibilitySize ? 2 : 5), spacing: 16
            ) {
                ForEach(categories, id: \.id) { category in
                    Button(action: action) {
                        VStack(spacing: 8) {
                            HomeCardImage(
                                url: category.imageURL, pipeline: pipeline, isActive: isActive,
                                size: CGSize(width: 48, height: 48))
                            Text(category.name).font(.caption).foregroundStyle(.primary)
                                .multilineTextAlignment(.center).fixedSize(
                                    horizontal: false, vertical: true
                                )
                                .accessibilityIdentifier("home.category.\(category.id).name")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
