import Foundation
import MallCore
import MallImages
import SwiftUI

@MainActor public struct CheckoutEntryView: View {
    private let accountID: Int64
    private let intent: BuyNowIntent
    private let loader: any CheckoutLoading
    private let isActive: Bool
    private let onRequestLogin: () -> Void
    private let imagePipeline: MallImagePipeline?
    private let onChooseAddress: (@escaping @MainActor (ShippingAddress) -> Void) -> Void
    public init(
        accountID: Int64, intent: BuyNowIntent, loader: any CheckoutLoading,
        isActive: Bool, imagePipeline: MallImagePipeline?, onRequestLogin: @escaping () -> Void,
        onChooseAddress: @escaping (@escaping @MainActor (ShippingAddress) -> Void) -> Void
    ) {
        self.onRequestLogin = onRequestLogin
        self.accountID = accountID; self.intent = intent; self.loader = loader
        self.isActive = isActive; self.imagePipeline = imagePipeline;
        self.onChooseAddress = onChooseAddress
    }
    public var body: some View {
        CheckoutScreen(
            accountID: accountID, intent: intent, loader: loader, isActive: isActive,
            pipeline: imagePipeline, onRequestLogin: onRequestLogin,
            onChooseAddress: onChooseAddress
        ).id("\(accountID):\(intent.id)")
    }
}
@MainActor private struct CheckoutScreen: View {
    @State private var model: CheckoutViewModel
    @State private var showsCoupons = false
    @Environment(\.scenePhase) private var scenePhase
    let onRequestLogin: () -> Void
    let isActive: Bool
    let pipeline: MallImagePipeline?
    let onChooseAddress: (@escaping @MainActor (ShippingAddress) -> Void) -> Void
    private let accent = Color(red: 0.29, green: 0.32, blue: 1)
    init(
        accountID: Int64, intent: BuyNowIntent, loader: any CheckoutLoading, isActive: Bool,
        pipeline: MallImagePipeline?, onRequestLogin: @escaping () -> Void,
        onChooseAddress: @escaping (@escaping @MainActor (ShippingAddress) -> Void) -> Void
    ) {
        _model = State(
            initialValue: CheckoutViewModel(accountID: accountID, intent: intent, loader: loader))
        self.onRequestLogin = onRequestLogin
        self.isActive = isActive; self.pipeline = pipeline; self.onChooseAddress = onChooseAddress
    }
    private struct ReadKey: Equatable { let active: Bool; let attempt: Int }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.loading { ProgressView("正在读取确认信息") }
                if let failure = model.failure {
                    VStack(spacing: 12) {
                        Text(failure == .authenticationRequired ? "请重新登录后确认订单" : "确认信息读取失败，请重试")
                        if failure == .authenticationRequired {
                            Button("重新登录") {
                                model.retry(); onRequestLogin()
                            }.accessibilityIdentifier("checkout.login")
                        } else {
                            Button("重试") { model.retry() }.accessibilityIdentifier("checkout.retry")
                        }
                    }.frame(maxWidth: .infinity).padding().accessibilityElement(children: .contain)
                        .accessibilityIdentifier("checkout.error")
                }
                Button {
                    onChooseAddress(model.addressSelection())
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            if let address = model.address {
                                Text(address.value.contact + "  " + address.value.phone)
                                Text(
                                    [
                                        address.value.province, address.value.city,
                                        address.value.district, address.value.address,
                                    ].joined(separator: " ")
                                )
                                .foregroundStyle(.secondary)
                            } else {
                                Label("请选择收货地址", systemImage: "mappin.and.ellipse")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).accessibilityIdentifier("checkout.address")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if let pipeline {
                                RemoteImage(
                                    url: model.intent.imageURL,
                                    targetSize: CGSize(width: 88, height: 88),
                                    contentMode: .fit, pipeline: pipeline, isEnabled: active)
                            } else {
                                Image(systemName: "photo").foregroundStyle(.secondary)
                            }
                        }.frame(width: 88, height: 88).background(
                            .quinary, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.intent.title).font(.headline)
                            Text(model.intent.specification).foregroundStyle(.secondary)
                            Text("数量：\(model.intent.quantity)").accessibilityIdentifier(
                                "checkout.quantity")
                            Text(model.intent.unitPriceYuan.formatted(.currency(code: "CNY")))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    LabeledContent(
                        "商品小计", value: model.intent.subtotalYuan.formatted(.currency(code: "CNY"))
                    )
                    .accessibilityIdentifier("checkout.subtotal")
                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
                Button {
                    showsCoupons = true
                } label: {
                    HStack {
                        Text("优惠券"); Spacer()
                        Text(
                            model.selectedCoupon?.title
                                ?? (model.coupons == nil ? "信息待确认" : "选择优惠券")
                        )
                        .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).disabled(model.coupons == nil)
                    .accessibilityIdentifier("checkout.coupons")
                if let notice = model.notice { Text(notice).foregroundStyle(.secondary) }
                Text("运费与优惠待确认，商品小计不代表最终应付金额。")
                    .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier(
                        "checkout.amountNotice")
            }.padding(16)
        }.accessibilityIdentifier("checkout.page").background(Color.primary.opacity(0.035))
            .navigationTitle("确认订单").navigationBarTitleDisplayMode(.inline).tint(accent)
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showsCoupons) {
                NavigationStack {
                    List {
                        Button("不使用优惠券") {
                            model.chooseCoupon(nil); showsCoupons = false
                        }
                        .accessibilityIdentifier("checkout.coupon.none")
                        if model.coupons?.isEmpty == true { Text("暂无优惠券") }
                        ForEach(model.coupons ?? []) { coupon in
                            Button {
                                model.chooseCoupon(coupon); showsCoupons = false
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(coupon.title).foregroundStyle(.primary)
                                    Text(coupon.description).font(.subheadline).foregroundStyle(
                                        .secondary)
                                    Text("优惠以结算确认为准").font(.footnote).foregroundStyle(.secondary)
                                }.padding(.vertical, 8)
                            }.disabled(coupon.availability() != .available)
                                .accessibilityIdentifier("checkout.coupon.\(coupon.id)")
                        }
                    }.navigationTitle("选择优惠券").navigationBarTitleDisplayMode(.inline)
                }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).tint(
                    accent)
            }
            .task(id: ReadKey(active: active, attempt: model.attempt)) {
                await model.activate(active)
            }
            .onDisappear { model.stop() }
    }
}
