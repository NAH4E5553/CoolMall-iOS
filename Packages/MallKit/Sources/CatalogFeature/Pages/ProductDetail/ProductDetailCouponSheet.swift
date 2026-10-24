import MallCore
import SwiftUI

/// A bottom overlay permits explicit outside-tap dismissal on phones as requested.
/// Expansions are local to this presentation; coupon reads remain page-owned.
struct ProductDetailCouponSheet: View {
    let coupons: [ProductDetailCoupon]
    let height: CGFloat
    let dismiss: () -> Void
    @ScaledMetric private var titleSize = 16.0
    @ScaledMetric private var couponTitleSize = 14.0
    @ScaledMetric private var titleLeading = 5.0
    @State private var expanded: Set<Int64> = []
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.32).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture(perform: dismiss)
                .accessibilityLabel("关闭优惠券弹框")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("detail.coupons.dismiss")
            VStack(spacing: 0) {
                Capsule().fill(ProductDetailStyle.onSurface(scheme).opacity(0.1)).frame(
                    width: 40, height: 4
                ).padding(
                    .top, 16)
                Text("领取优惠券").font(.system(size: titleSize, weight: .bold)).padding(.vertical, 20)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(coupons) { coupon in card(coupon) }
                    }.padding(.horizontal, 12).padding(.bottom, 24)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(
                ProductDetailStyle.background(scheme),
                in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
            )
            .accessibilityIdentifier("detail.coupons.sheet")
        }
        .foregroundStyle(ProductDetailStyle.onSurface(scheme))
        .ignoresSafeArea(edges: .bottom)
        .accessibilityAction(.escape, dismiss)
    }
    private func card(_ coupon: ProductDetailCoupon) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image("detail-coupon", bundle: .module).resizable().frame(width: 26, height: 26)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        ProductDetailStyle.accent.opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(coupon.title).font(.system(size: couponTitleSize, weight: .bold))
                        .lineSpacing(titleLeading)
                        .lineLimit(2).truncationMode(.tail)
                    if let endTime = coupon.endTime {
                        Text("有效期至 \(endTime)").font(.caption).foregroundStyle(
                            ProductDetailStyle.tertiary(scheme))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    ProductDetailPriceView(amount: coupon.amountYuan, compact: true)
                    if let minimum = coupon.minimumSpendYuan {
                        Text(minimum > 0 ? "满\(ProductDetailStyle.number(minimum))元可用" : "无门槛")
                            .font(.caption).foregroundStyle(ProductDetailStyle.secondary(scheme))
                    }
                }
            }.padding(12)
            Divider()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if !coupon.description.isEmpty {
                        Button {
                            if expanded.contains(coupon.id) {
                                expanded.remove(coupon.id)
                            } else {
                                expanded.insert(coupon.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("使用说明")
                                Image(
                                    systemName: expanded.contains(coupon.id)
                                        ? "chevron.up" : "chevron.down"
                                )
                                .foregroundStyle(ProductDetailStyle.onSurface(scheme).opacity(0.6))
                            }.font(.caption).foregroundStyle(ProductDetailStyle.tertiary(scheme))
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(expanded.contains(coupon.id) ? "已展开" : "已收起")
                        .accessibilityIdentifier("detail.coupon.rules.\(coupon.id)")
                        if expanded.contains(coupon.id) {
                            Text(coupon.description).font(.caption).foregroundStyle(
                                ProductDetailStyle.tertiary(scheme)
                            )
                            .accessibilityIdentifier("detail.coupon.description.\(coupon.id)")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("立即领取") {}.font(.system(size: couponTitleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(ProductDetailStyle.accent, in: Capsule())
                    .accessibilityHint("功能暂未实现")
            }.padding(12)
        }.background(ProductDetailStyle.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
    }
}
