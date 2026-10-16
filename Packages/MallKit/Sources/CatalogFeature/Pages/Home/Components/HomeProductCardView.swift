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

/// Each source presentation keeps its own typography and line rules.
struct HomeProductCardView: View {
    enum Role { case featured, recommendation, goods }
    let product: HomeProductSummary
    let key: String
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let role: Role
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var titleSize = 14.0
    @ScaledMetric(relativeTo: .caption) private var smallSize = 12.0
    @ScaledMetric(relativeTo: .caption2) private var subtitleSize = 11.0
    @ScaledMetric(relativeTo: .headline) private var priceSize = 18.0

    var body: some View {
        Button(action: action) {
            Group {
                if role == .recommendation {
                    HomeRecommendationLayout {
                        productImage(size: CGSize(width: 100, height: 100))
                        textDetails
                        price
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay {
                                GeometryReader { geometry in
                                    productImage(size: geometry.size)
                                }
                            }
                        details
                    }
                }
            }
            .padding(role == .featured ? 0 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if role != .featured {
                    RoundedRectangle(cornerRadius: 12).fill(surface)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.\(key).\(product.id).card")
    }

    private var surface: Color {
        colorScheme == .dark ? Color(white: 0.12) : .white
    }
    private var titleColor: Color {
        Color(white: colorScheme == .dark ? 209.0 / 255 : 24.0 / 255)
    }
    private func productImage(size: CGSize) -> some View {
        HomeCardImage(url: product.imageURL, pipeline: pipeline, isActive: isActive, size: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            textDetails
            price
        }
    }
    private var textDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(product.title)
                .font(.system(size: role == .featured ? smallSize : titleSize))
                // SF metrics differ from Android; add leading without fixing a text box.
                .lineSpacing(role == .featured ? smallSize * 0.3 : titleSize * 0.35)
                .padding(.vertical, role == .featured ? smallSize * 0.15 : titleSize * 0.175)
                .lineLimit(role == .featured ? 1 : role == .recommendation ? 2 : nil)
                .truncationMode(.tail)
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home.\(key).\(product.id).title")
            if role != .featured, let subtitle = product.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: subtitleSize))
                    .lineSpacing(subtitleSize * 0.3)
                    .padding(.vertical, subtitleSize * 0.15)
                    .lineLimit(role == .recommendation ? 1 : 2)
                    .truncationMode(.tail)
                    .foregroundStyle(Color(white: 178.0 / 255))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.\(key).\(product.id).subtitle")
            }
        }
    }
    private var price: some View {
        // Currency formatting stays Decimal-based, including fractional yuan.
        let formatted = product.priceYuan.formatted(
            .currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
        let fractionStart = formatted.lastIndex(of: ".") ?? formatted.endIndex
        let integerStart = formatted.firstIndex(where: { $0.isNumber }) ?? formatted.startIndex
        let prefix = String(formatted[..<integerStart])
        let integer = String(formatted[integerStart..<fractionStart])
        let fraction = String(formatted[fractionStart...])
        return
            (Text(prefix).font(.system(size: smallSize))
            + Text(integer).font(
                .system(size: role == .featured ? titleSize : priceSize, weight: .bold))
            + Text(fraction).font(.system(size: smallSize)))
            .foregroundStyle(Color(red: 1, green: 43.0 / 255, blue: 43.0 / 255))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(formatted)
            .accessibilityIdentifier("home.\(key).\(product.id).price")
    }
}

/// Only the full amount's intrinsic width chooses the footer. Titles are always
/// measured in their actual right-hand column, so wrapping titles cannot force
/// an otherwise fitting amount out of that column.
private struct HomeRecommendationLayout: Layout {
    private let imageWidth = 100.0
    private let spacing = 12.0
    private func plan(width: CGFloat, subviews: Subviews) -> (
        textWidth: CGFloat, priceX: CGFloat, priceY: CGFloat, priceWidth: CGFloat, height: CGFloat
    ) {
        let textWidth = max(0, width - imageWidth - spacing)
        let textHeight = subviews[1].sizeThatFits(ProposedViewSize(width: textWidth, height: nil))
            .height
        let footer = subviews[2].sizeThatFits(.unspecified).width > textWidth
        let priceWidth = footer ? width : textWidth
        let priceY = (footer ? max(imageWidth, textHeight) : textHeight) + 4
        let priceHeight = subviews[2].sizeThatFits(ProposedViewSize(width: priceWidth, height: nil))
            .height
        return (
            textWidth, footer ? 0 : imageWidth + spacing, priceY, priceWidth,
            max(imageWidth, priceY + priceHeight)
        )
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 346
        return CGSize(width: width, height: plan(width: width, subviews: subviews).height)
    }
    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let layout = plan(width: bounds.width, subviews: subviews)
        subviews[0].place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: imageWidth, height: imageWidth))
        subviews[1].place(
            at: CGPoint(x: bounds.minX + imageWidth + spacing, y: bounds.minY), anchor: .topLeading,
            proposal: ProposedViewSize(width: layout.textWidth, height: nil))
        subviews[2].place(
            at: CGPoint(x: bounds.minX + layout.priceX, y: bounds.minY + layout.priceY),
            anchor: .topLeading, proposal: ProposedViewSize(width: layout.priceWidth, height: nil))
    }
}
