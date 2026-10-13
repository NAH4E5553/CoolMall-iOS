import Foundation
import MallCore
import MallImages
import SwiftUI

struct HomeCardImage: View {
    let url: URL?
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let size: CGSize
    var body: some View {
        Group {
            if let pipeline {
                RemoteImage(
                    url: url, targetSize: size, contentMode: .fit, pipeline: pipeline,
                    isEnabled: isActive)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                    .frame(width: size.width, height: size.height)
            }
        }.accessibilityHidden(true)
    }
}

struct HomeProductCardView: View {
    let product: HomeProductSummary
    let key: String
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let horizontal: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if horizontal {
                    HStack(alignment: .top, spacing: 12) {
                        image
                        details.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        image; details
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("home.\(key).\(product.id).card")
    }

    private var image: some View {
        HomeCardImage(
            url: product.imageURL, pipeline: pipeline, isActive: isActive,
            size: CGSize(width: horizontal ? 88 : 120, height: horizontal ? 88 : 120)
        )
        .frame(maxWidth: horizontal ? nil : .infinity)
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.title).font(.body).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home.\(key).\(product.id).title")
            if let subtitle = product.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(
                product.priceYuan,
                format: .currency(code: "CNY").locale(Locale(identifier: "zh_CN"))
            )
            .font(.headline).foregroundStyle(.primary)
            .accessibilityIdentifier("home.\(key).\(product.id).price")
        }
    }
}
