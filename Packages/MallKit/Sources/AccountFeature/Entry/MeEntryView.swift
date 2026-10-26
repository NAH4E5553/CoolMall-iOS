import MallCore
import MallImages
import SwiftUI

@MainActor public struct MeEntryView: View {
    private let state: AccountState
    private let imagePipeline: MallImagePipeline?
    private let footprints: (any FootprintBrowsing)?
    private let isActive: Bool
    private let onOpenFootprints: () -> Void
    private let onOpenProduct: (Int64) -> Void
    private let onOpenAddresses: () -> Void
    private let onOpenCoupons: () -> Void
    private let onOpenOrders: (OrderFilter) -> Void
    private let openAccount: () -> Void
    @State private var unavailable = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public init(
        state: AccountState, imagePipeline: MallImagePipeline?,
        footprints: (any FootprintBrowsing)? = nil, isActive: Bool = true,
        onOpenFootprints: @escaping () -> Void = {},
        onOpenCoupons: @escaping () -> Void = {},
        onOpenAddresses: @escaping () -> Void = {},
        onOpenOrders: @escaping (OrderFilter) -> Void = { _ in },
        onOpenProduct: @escaping (Int64) -> Void = { _ in }, openAccount: @escaping () -> Void
    ) {
        self.onOpenOrders = onOpenOrders
        self.onOpenAddresses = onOpenAddresses
        self.onOpenCoupons = onOpenCoupons
        self.footprints = footprints; self.isActive = isActive;
        self.onOpenFootprints = onOpenFootprints; self.onOpenProduct = onOpenProduct
        self.state = state; self.imagePipeline = imagePipeline; self.openAccount = openAccount
    }
    private var accountTitle: String {
        switch state {
        case .guest: "未登录"
        case .signedIn(let profile):
            profile.nickname.flatMap { $0.isEmpty ? nil : $0 } ?? "已登录"
        }
    }
    private var accountSubtitle: String {
        switch state {
        case .guest: "点击登录账号"
        case .signedIn(let profile):
            profile.phone.flatMap { $0.isEmpty ? nil : "手机号：" + $0 } ?? "查看个人资料"
        }
    }
    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Button(action: openAccount) {
                    HStack(spacing: 16) {
                        AccountAvatar(profile: state.profile, pipeline: imagePipeline)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(accountTitle)
                                .font(.title2.bold()).foregroundStyle(.primary)
                            Text(accountSubtitle)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("me.account")
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 16) { membershipContent }
                    } else {
                        HStack { membershipContent }
                    }
                }
                .padding(16).foregroundStyle(Color(red: 0.87, green: 0.65, blue: 0.43))
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 18))
                VStack(spacing: 16) {
                    Button {
                        onOpenOrders(.all)
                    } label: {
                        sectionHeader(
                            "我的订单", icon: "list.bullet.rectangle.fill", tint: accountAccent)
                    }.buttonStyle(.plain).accessibilityIdentifier("me.orders.all")
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 130 : 56),
                                spacing: 10)
                        ], spacing: 16
                    ) {
                        ForEach(
                            Array(
                                zip(
                                    ["待付款", "待发货", "待收货", "待评价", "退款/售后"],
                                    [
                                        "wallet.bifold", "shippingbox", "truck.box", "text.bubble",
                                        "arrow.uturn.backward.circle",
                                    ])), id: \.0
                        ) { label, icon in
                            Button {
                                let filters: [String: OrderFilter] = [
                                    "待付款": .unpaid, "待发货": .unshipped, "待收货": .unreceived,
                                    "待评价": .unevaluated, "退款/售后": .afterSale,
                                ]
                                if let filter = filters[label] { onOpenOrders(filter) }
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: icon).font(.title2);
                                    Text(label).font(.caption)
                                }
                                .frame(maxWidth: .infinity, minHeight: 62)
                            }.buttonStyle(.plain).accessibilityIdentifier("me.orders.\(label)")
                        }
                    }
                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
                if let footprints {
                    FootprintPreviewView(
                        store: footprints, pipeline: imagePipeline, isActive: isActive,
                        onShowAll: onOpenFootprints, onOpenProduct: onOpenProduct
                    ).id(footprints.scope)
                }
                VStack(spacing: 0) {
                    menu("优惠券", icon: "ticket.fill", tint: .blue, action: onOpenCoupons)
                        .accessibilityIdentifier("me.coupons")
                    Divider().padding(.leading, 50)
                    menu("收货地址", icon: "mappin.circle.fill", tint: .green, action: onOpenAddresses)
                        .accessibilityIdentifier("me.addresses")
                    Divider().padding(.leading, 50)
                    menu("在线客服", icon: "headphones", tint: .pink)
                    Divider().padding(.leading, 50)
                    menu("意见反馈", icon: "lightbulb.fill", tint: .orange)
                    Divider().padding(.leading, 50)
                    menu("关于我们", icon: "info.circle.fill", tint: .purple)
                }.background(.background, in: RoundedRectangle(cornerRadius: 18))
                menu("设置", icon: "gearshape.fill", tint: .teal)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
            }.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(.quinary)
        .toolbar(.hidden, for: .navigationBar)
        .modifier(DeferredNotice(isPresented: $unavailable))
        .accessibilityIdentifier("me.page")
    }
    @ViewBuilder private var membershipContent: some View {
        Label("会员立享5大权益！", systemImage: "crown.fill").font(.headline)
        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
        Button("立即开通") { unavailable = true }.font(.subheadline)
            .padding(8).overlay(
                Capsule().stroke(Color(red: 0.87, green: 0.65, blue: 0.43), lineWidth: 1))
    }
    private func sectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack {
            Label {
                Text(title).foregroundStyle(.primary)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .font(.headline)
            Spacer()
            HStack(spacing: 4) {
                Text("查看全部"); Image(systemName: "chevron.right")
            }.font(.subheadline).foregroundStyle(.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle())
    }
    private func menu(_ title: String, icon: String, tint: Color, action: (() -> Void)? = nil)
        -> some View
    {
        Button {
            if let action { action() } else { unavailable = true }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
                Text(title).foregroundStyle(.primary)
                Spacer();
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }.padding(18).frame(minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
