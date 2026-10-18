import MallCore
import SwiftUI

struct HomeCouponSectionView: View {
    let coupons: [HomeCouponSummary]
    let action: () -> Void
    var body: some View {
        HomeSectionView(title: nil, key: "coupon") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(coupons, id: \.id) { coupon in
                        Button(action: action) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(coupon.title).font(.body).foregroundStyle(.primary)
                                    .lineLimit(1).truncationMode(.tail)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("home.coupon.\(coupon.id).title")
                                Spacer(minLength: 0)
                                Text("领取").font(.subheadline).fixedSize()
                                    .accessibilityIdentifier("home.coupon.\(coupon.id).claim")
                                    .foregroundStyle(
                                        Color(red: 1, green: 43.0 / 255, blue: 43.0 / 255))
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal)
                    }
                }
            }
        }
    }
}
