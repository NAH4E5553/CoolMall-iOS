import MallCore
import SwiftUI

/// Selection belongs to this display row; App handles the selected coupon intent.
struct HomeCouponSectionView: View {
    let coupons: [HomeCouponSummary]
    let action: (HomeCouponSummary) -> Void
    @State private var selectedID: Int64?

    private var ids: [Int64] { coupons.map(\.id) }
    private var currentCoupon: HomeCouponSummary? {
        coupons.first(where: { $0.id == selectedID }) ?? coupons.first
    }
    private var pagerSelection: Binding<Int64> {
        Binding(
            get: { currentCoupon?.id ?? 0 },
            set: { id in
                guard ids.contains(id) else { return }
                selectedID = id
            })
    }

    var body: some View {
        HomeSectionView(title: nil, key: "coupon") {
            HStack(spacing: 12) {
                Text(" ").font(.body).hidden()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay {
                        TabView(selection: pagerSelection) {
                            ForEach(coupons, id: \.id) { coupon in
                                Text(coupon.title).font(.body).foregroundStyle(.primary)
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("home.coupon.\(coupon.id).title")
                                    .tag(coupon.id)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .accessibilityIdentifier("home.coupon.pager")
                    }
                Button {
                    if let coupon = currentCoupon { action(coupon) }
                } label: {
                    Text("领取").font(.subheadline).fixedSize()
                        .foregroundStyle(Color(red: 1, green: 43.0 / 255, blue: 43.0 / 255))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("领取，\(currentCoupon?.title ?? "优惠券")")
                .accessibilityIdentifier("home.coupon.\(currentCoupon?.id ?? 0).claim")
            }
            .padding(.horizontal, 12)
        }
        .onChange(of: ids, initial: true) { _, _ in
            selectedID = currentCoupon?.id
        }
    }
}
