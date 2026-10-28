import MallCore
import MallImages
import SwiftUI

/// Full review layout follows Android CommentCard; no image viewer or write action.
struct ProductReviewCard: View {
    let review: ProductDetailReview
    let createdAt: String?
    let pipeline: MallImagePipeline?
    let isActive: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric private var bodySize = 14.0
    @ScaledMetric private var timeSize = 11.0
    @ScaledMetric private var bodyLeading = 6.0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductDetailImage(url: review.avatarURL, pipeline: pipeline, isActive: isActive)
                .frame(width: 40, height: 40).clipShape(Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                header
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image("detail-star", bundle: .module).resizable().frame(
                            width: 16, height: 16
                        )
                        .foregroundStyle(
                            index < review.starCount
                                ? ProductDetailStyle.ratingActive
                                : ProductDetailStyle.ratingInactive)
                    }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("\(review.starCount)星")
                .padding(.top, 4).padding(.bottom, 12)
                if !review.content.isEmpty {
                    Text(review.content).font(.system(size: bodySize)).lineSpacing(bodyLeading)
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, 12)
                }
                if !review.imageURLs.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                        spacing: 8
                    ) {
                        ForEach(Array(review.imageURLs.prefix(9).enumerated()), id: \.offset) {
                            index, url in
                            ProductDetailImage(url: url, pipeline: pipeline, isActive: isActive)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(
                                    "评价图片\(index + 1)，共\(min(9, review.imageURLs.count))张"
                                )
                                .accessibilityIdentifier("reviews.image.\(review.id).\(index)")
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).foregroundStyle(ProductDetailStyle.onSurface(scheme))
        .background(ProductDetailStyle.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviews.card.\(review.id)")
    }

    private var header: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    nickname; timestamp
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    nickname.layoutPriority(1)
                    Spacer(minLength: 0)
                    timestamp
                }
            }
        }
    }
    private var nickname: some View {
        Text(review.nickname ?? "匿名用户").font(.system(size: bodySize))
            .fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var timestamp: some View {
        if let createdAt {
            Text(createdAt).font(.system(size: timeSize))
                .foregroundStyle(ProductDetailStyle.tertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
