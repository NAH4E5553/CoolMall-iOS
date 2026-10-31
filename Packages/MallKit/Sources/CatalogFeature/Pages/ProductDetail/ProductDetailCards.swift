import MallCore
import MallImages
import SwiftUI

struct ProductDetailInfoCard: View {
    let detail: ProductDetailSnapshot
    let selected: ProductSpecification?
    let showCoupons: () -> Void
    let showSpecifications: () -> Void
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric private var titleSize = 16.0
    @ScaledMetric private var bodySize = 12.0
    @ScaledMetric private var labelSize = 11.0
    @ScaledMetric private var titleLeading = 5.0
    @ScaledMetric private var bodyLeading = 4.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    price
                    Spacer(minLength: 8)
                    sold
                }
                VStack(alignment: .leading, spacing: 8) {
                    price; sold
                }
            }
            if !detail.coupons.isEmpty {
                ProductDetailCouponFlow {
                    ForEach(detail.coupons) { coupon in
                        Button(action: showCoupons) {
                            HStack(spacing: 4) {
                                Image("detail-coupon", bundle: .module).resizable().frame(
                                    width: 12, height: 12)
                                Text(coupon.tagText)
                            }
                            .font(.system(size: labelSize, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(ProductDetailStyle.danger)
                            .background(
                                RoundedRectangle(cornerRadius: 4).stroke(
                                    ProductDetailStyle.danger, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("detail.coupon.\(coupon.id)")
                    }
                }
                .padding(.top, 8)
            }
            Text(detail.title).font(.system(size: titleSize, weight: .bold)).lineSpacing(
                titleLeading
            )
            .lineLimit(2).truncationMode(.tail).padding(.top, 12)
            .accessibilityIdentifier("detail.loaded")
            if let subtitle = detail.subtitle {
                Text(subtitle).font(.system(size: bodySize)).lineSpacing(bodyLeading)
                    .foregroundStyle(ProductDetailStyle.onSurface(scheme).opacity(0.7))
                    .lineLimit(2).truncationMode(.tail).padding(.top, 4)
                    .accessibilityIdentifier("detail.subtitle")
            }
            if !detail.isAvailable {
                Text("商品已下架").font(.footnote).foregroundStyle(ProductDetailStyle.secondary(scheme))
                    .accessibilityIdentifier("detail.unavailable")
            }
            Button(action: showSpecifications) {
                HStack(spacing: 8) {
                    Image("detail-cube", bundle: .module).resizable().frame(width: 20, height: 20)
                        .foregroundStyle(
                            ProductDetailStyle.onSurface(scheme).opacity(0.6))
                    Text(selected.map { "已选：" + $0.name } ?? "选择规格")
                        .font(.system(size: bodySize)).foregroundStyle(
                            ProductDetailStyle.onSurface(scheme).opacity(0.8)
                        )
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(
                        ProductDetailStyle.onSurface(scheme).opacity(0.4))
                }
                .padding(12).frame(minHeight: 44).contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8).stroke(
                        ProductDetailStyle.border(scheme), lineWidth: 1.2))
            }
            .buttonStyle(.plain).disabled(!detail.isAvailable).padding(.top, 12)
            .accessibilityIdentifier("detail.openSpecifications")
        }
        .padding(12).background(
            ProductDetailStyle.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
    }
    private var price: some View {
        ProductDetailPriceView(amount: selected?.priceYuan ?? detail.priceYuan)
            .accessibilityIdentifier("detail.price")
    }
    private var sold: some View {
        Text(verbatim: "已售 \(detail.sold)").font(.system(size: labelSize, weight: .medium))
            .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
            .background(ProductDetailStyle.accent, in: Capsule())
            .accessibilityIdentifier("detail.sold")
    }
}

extension ProductDetailCoupon {
    var tagText: String {
        let amount = ProductDetailStyle.number(amountYuan)
        if let minimumSpendYuan, minimumSpendYuan > 0 {
            return "满\(ProductDetailStyle.number(minimumSpendYuan))减\(amount)元"
        }
        return "减\(amount)元"
    }
}

/// Measures each label once and wraps on narrow/large-text layouts, matching Android FlowRow.
struct ProductDetailCouponFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for (view, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            view.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }
    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0
        return subviews.map { view in
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            let frame = CGRect(x: x, y: y, width: min(width, size.width), height: size.height)
            x += frame.width + spacing; rowHeight = max(rowHeight, size.height)
            return frame
        }
    }
}

struct ProductDetailDeliveryCard: View {
    @ScaledMetric private var labelSize = 14.0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            ProductDetailSectionTitle(title: "发货与服务").padding(12)
            Divider()
            row("发货", "北京市 北平").accessibilityIdentifier("detail.delivery")
            Divider()
            row("服务", "7天无理由退货 · 运费险 · 48小时发货")
        }
        .background(ProductDetailStyle.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).font(.system(size: labelSize))
            Spacer(minLength: 0)
            Text(value).font(.caption).foregroundStyle(ProductDetailStyle.secondary(scheme))
                .multilineTextAlignment(.trailing)
        }.padding(12)
    }
}

struct ProductDetailReviewsCard: View {
    @ScaledMetric private var bodyLeading = 4.0
    let reviews: [ProductDetailReview]
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let showAll: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ProductDetailSectionTitle(title: "商品评价")
                Button(action: showAll) {
                    HStack(spacing: 4) {
                        Text("查看全部").font(.caption)
                            .foregroundStyle(ProductDetailStyle.secondary(scheme))
                        Image("detail-right", bundle: .module).resizable().frame(
                            width: 16, height: 16
                        )
                        .foregroundStyle(Color(white: 163 / 255))
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("detail.reviews.all")
            }.padding(12)
            ForEach(Array(reviews.prefix(2).enumerated()), id: \.element.id) { index, review in
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    ProductDetailImage(
                        url: review.avatarURL, pipeline: pipeline, isActive: isActive
                    )
                    .frame(width: 32, height: 32).clipShape(Circle()).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(review.nickname ?? "匿名用户").font(.caption)
                        HStack(spacing: 2) {
                            ForEach(0..<5) { star in
                                Image("detail-star", bundle: .module).resizable().frame(
                                    width: 14, height: 14
                                )
                                .foregroundStyle(
                                    star < review.starCount
                                        ? ProductDetailStyle.ratingActive
                                        : ProductDetailStyle.ratingInactive)
                            }
                        }
                        .accessibilityElement(children: .ignore).accessibilityLabel(
                            "\(review.starCount)星"
                        )
                        .accessibilityIdentifier("detail.review.stars.\(review.id)")
                        if !review.content.isEmpty {
                            Text(review.content).font(.caption).lineSpacing(bodyLeading)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let url = review.imageURLs.first {
                        ProductDetailImage(url: url, pipeline: pipeline, isActive: isActive)
                            .frame(width: 60, height: 60).clipShape(
                                RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                if review.imageURLs.count > 1 {
                                    Text("+\(review.imageURLs.count - 1)").font(.caption2)
                                        .foregroundStyle(.white)
                                        .padding(4).background(
                                            .black.opacity(0.4),
                                            in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                    }
                }
                .padding(12).accessibilityElement(children: .contain)
                .accessibilityIdentifier("detail.review.\(review.id)")
            }
        }.background(ProductDetailStyle.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProductDetailImage: View {
    let url: URL?
    let pipeline: MallImagePipeline?
    let isActive: Bool
    var body: some View {
        GeometryReader { proxy in
            if let pipeline {
                RemoteImage(
                    url: url, targetSize: proxy.size, contentMode: .fill,
                    pipeline: pipeline, isEnabled: isActive)
            } else {
                Rectangle().fill(.quaternary).overlay {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
    }
}
