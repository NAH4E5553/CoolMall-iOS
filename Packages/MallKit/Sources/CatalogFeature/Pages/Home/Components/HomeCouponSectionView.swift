import MallCore
import SwiftUI

struct HomeCouponSectionView: View {
    let coupons: [HomeCouponSummary]
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HomeSectionView(title: "优惠券", key: "coupon") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(coupons, id: \.id) { coupon in
                        Button(action: action) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(coupon.title).font(.body).foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("home.coupon.\(coupon.id).title")
                                Spacer(minLength: 0)
                                Text("领取").font(.subheadline).fixedSize()
                            }.padding(12).background(
                                .quinary, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                            .frame(width: typeSize.isAccessibilitySize ? 320 : 260)
                    }
                }
            }
        }
    }
}
