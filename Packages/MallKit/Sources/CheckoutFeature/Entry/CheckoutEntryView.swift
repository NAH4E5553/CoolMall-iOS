import Foundation
import MallCore
import MallDesignSystem
import MallImages
import SwiftUI

@MainActor public struct CheckoutEntryView: View {
    private let accountID: Int64
    private let intent: CheckoutIntent
    private let loader: any CheckoutLoading
    private let creator: (any OrderCreating)?
    private let isActive: Bool
    private let onRequestLogin: () -> Void
    private let imagePipeline: MallImagePipeline?
    private let onChooseAddress: (@escaping @MainActor (ShippingAddress) -> Void) -> Void
    private let onCreated: (Int64) -> Void
    private let cart: (any ShoppingCart)?
    private let onCartCleanupFailure: () -> Void
    public init(
        accountID: Int64, intent: CheckoutIntent, loader: any CheckoutLoading,
        isActive: Bool, imagePipeline: MallImagePipeline?, onRequestLogin: @escaping () -> Void,
        onChooseAddress: @escaping (@escaping @MainActor (ShippingAddress) -> Void) -> Void,
        creator: (any OrderCreating)? = nil, cart: (any ShoppingCart)? = nil,
        onCartCleanupFailure: @escaping () -> Void = {},
        onCreated: @escaping (Int64) -> Void = { _ in }
    ) {
        self.accountID = accountID; self.intent = intent; self.loader = loader
        self.isActive = isActive; self.imagePipeline = imagePipeline
        self.onRequestLogin = onRequestLogin; self.onChooseAddress = onChooseAddress
        self.creator = creator; self.onCreated = onCreated; self.cart = cart;
        self.onCartCleanupFailure = onCartCleanupFailure
    }
    public var body: some View {
        CheckoutScreen(
            accountID: accountID, intent: intent, loader: loader, creator: creator, cart: cart,
            onCartCleanupFailure: onCartCleanupFailure, isActive: isActive, pipeline: imagePipeline,
            onRequestLogin: onRequestLogin,
            onChooseAddress: onChooseAddress, onCreated: onCreated
        ).id("\(accountID):\(intent.id)")
    }
}
let checkoutAccent = Color(red: 0.29, green: 0.32, blue: 1)
@MainActor private struct CheckoutScreen: View {
    @State private var model: CheckoutViewModel
    @State private var showsCoupons = false
    // Immutable selection at presentation; the ViewModel still owns the live choice.
    @State private var presentedSelection: Int64?
    @State private var expanded: Set<Int64> = []
    @FocusState private var remarkFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    let onRequestLogin: () -> Void
    let isActive: Bool
    let pipeline: MallImagePipeline?
    let onChooseAddress: (@escaping @MainActor (ShippingAddress) -> Void) -> Void
    let onCreated: (Int64) -> Void
    let onCartCleanupFailure: () -> Void
    init(
        accountID: Int64, intent: CheckoutIntent, loader: any CheckoutLoading,
        creator: (any OrderCreating)?, cart: (any ShoppingCart)?,
        onCartCleanupFailure: @escaping () -> Void,
        isActive: Bool, pipeline: MallImagePipeline?,
        onRequestLogin: @escaping () -> Void,
        onChooseAddress: @escaping (@escaping @MainActor (ShippingAddress) -> Void) -> Void,
        onCreated: @escaping (Int64) -> Void
    ) {
        _model = State(
            initialValue: CheckoutViewModel(
                accountID: accountID, intent: intent,
                loader: loader, creator: creator, cart: cart))
        self.onRequestLogin = onRequestLogin; self.isActive = isActive; self.pipeline = pipeline
        self.onChooseAddress = onChooseAddress; self.onCreated = onCreated;
        self.onCartCleanupFailure = onCartCleanupFailure
    }
    private struct ReadKey: Equatable { let active: Bool; let attempt: Int }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.loading { ProgressView("正在读取确认信息") }
                    if let failure = model.failure {
                        VStack(spacing: 12) {
                            Text(failure == .authenticationRequired ? "请重新登录后确认订单" : "确认信息读取失败，请重试")
                            if failure == .authenticationRequired {
                                Button("重新登录") {
                                    model.retry(); onRequestLogin()
                                }
                                .accessibilityIdentifier("checkout.login")
                            } else {
                                Button("重试") { model.retry() }.accessibilityIdentifier(
                                    "checkout.retry")
                            }
                        }.frame(maxWidth: .infinity).padding().accessibilityElement(
                            children: .contain
                        )
                        .accessibilityIdentifier("checkout.error")
                    }
                    addressCard
                    productCards
                    if model.intent.pricesChanged {
                        Text("商品价格已更新，请核对后提交").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("checkout.priceChange")
                    }
                    VStack(spacing: 0) {
                        sectionTitle("价格明细")
                        amountRow(
                            "商品总价", symbol: "storefront", value: money(model.intent.subtotalYuan),
                            stacked: typeSize.isAccessibilitySize
                        )
                        .accessibilityIdentifier("checkout.subtotal")
                        Divider()
                        Button {
                            remarkFocused = false; presentedSelection = model.selectedCoupon?.id;
                            showsCoupons = true
                        } label: {
                            HStack {
                                Label("优惠券", systemImage: "ticket"); Spacer()
                                Text(
                                    model.selectedCoupon?.title
                                        ?? (model.coupons == nil ? "信息待确认" : "选择")
                                )
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.padding(16).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(
                            model.coupons == nil || model.loading || model.submitting
                                || model.writeLocked
                        )
                        .accessibilityIdentifier("checkout.coupons")
                        if let estimate = model.estimate, estimate.discountYuan > 0 {
                            Divider()
                            amountRow(
                                "优惠券折扣", symbol: "yensign.circle",
                                value: "−" + money(estimate.discountYuan), red: true,
                                stacked: typeSize.isAccessibilitySize
                            )
                            .accessibilityIdentifier("checkout.discount")
                        }
                        Divider()
                        amountRow(
                            "合计", symbol: "yensign.circle",
                            value: model.estimate.map { money($0.totalYuan) } ?? "待确认",
                            stacked: typeSize.isAccessibilitySize
                        )
                        .accessibilityIdentifier("checkout.total")
                    }.background(.background, in: RoundedRectangle(cornerRadius: 18))
                    VStack(spacing: 12) {
                        sectionTitle("订单备注")
                        TextField("选填，付款后商家可见", text: $model.remark, axis: .vertical)
                            .lineLimit(4...6).focused($remarkFocused).padding(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14).stroke(
                                    remarkFocused ? checkoutAccent : Color.secondary.opacity(0.15),
                                    lineWidth: remarkFocused ? 2 : 1)
                            )
                            .overlay(alignment: .topLeading) {
                                if remarkFocused || !model.remark.isEmpty {
                                    Text("订单备注").font(.caption).foregroundStyle(
                                        remarkFocused ? checkoutAccent : .secondary
                                    )
                                    .padding(.horizontal, 4).background(.background).offset(
                                        x: 12, y: -7)
                                }
                            }.padding(.horizontal, 12).padding(.bottom, 14)
                            .disabled(model.submitting || model.writeLocked)
                            .accessibilityIdentifier("checkout.remark")
                    }.background(.background, in: RoundedRectangle(cornerRadius: 18))
                    if let notice = model.notice {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("优惠按当前券门槛估算，最终金额以创建的订单为准。")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier(
                            "checkout.amountNotice")
                }.padding(12)
            }.accessibilityIdentifier("checkout.page")
                .accessibilityHidden(showsCoupons).allowsHitTesting(!showsCoupons)
            if showsCoupons {
                FixedBottomSheet(title: "选择优惠券", onDismiss: { showsCoupons = false }) {
                    ScrollView {
                        VStack(spacing: 12) {
                            if model.coupons?.isEmpty == true { Text("暂无优惠券").padding() }
                            ForEach(model.coupons ?? []) { coupon in couponCard(coupon) }
                        }.padding(.horizontal, 16).padding(.bottom, 24)
                    }.background(Color.primary.opacity(0.035)).accessibilityIdentifier(
                        "checkout.coupon.list")
                }.zIndex(2)
            }
            if let failure = model.writeFailure {
                Text(failure.message).font(.subheadline).foregroundStyle(.white).padding(14)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .padding(24).allowsHitTesting(false).accessibilityIdentifier("checkout.toast")
                    .task(id: failure) {
                        try? await Task.sleep(for: .seconds(3))
                        if !Task.isCancelled { model.clearWriteFailure() }
                    }
            }
        }.background(Color.primary.opacity(0.035)).tint(checkoutAccent)
            .navigationTitle("确认订单").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !showsCoupons {
                    let layout =
                        typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout())
                    layout {
                        Text(model.estimate.map { money($0.totalYuan) } ?? "金额待确认")
                            .font(.title2.bold()).foregroundStyle(.red)
                            .lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier(
                                "checkout.payable")
                        if !typeSize.isAccessibilitySize { Spacer() }
                        Button(model.submitting ? "正在提交" : "提交订单") {
                            remarkFocused = false
                            Task {
                                if let id = await model.submit() {
                                    if model.cartCleanupFailed { onCartCleanupFailure() };
                                    onCreated(id)
                                }
                            }
                        }.bold().lineLimit(1).padding(.horizontal, 20).padding(.vertical, 14)
                            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                            .foregroundStyle(.white).background(
                                checkoutAccent.opacity(model.canSubmit ? 1 : 0.45),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .disabled(!model.canSubmit).accessibilityIdentifier("checkout.submit")
                    }.padding(12).background(.background)
                }
            }
            .refreshable { await model.refresh() }
            .task(id: ReadKey(active: active, attempt: model.attempt)) {
                await model.activate(active)
            }
            .onChange(of: model.loading) { _, loading in
                if loading { showsCoupons = false }
            }
            .onChange(of: model.coupons) { _, _ in showsCoupons = false }
            .onChange(of: model.selectedCoupon?.id) { _, _ in showsCoupons = false }
            .onChange(of: model.recoveredOrderID) { _, id in
                if active, let id {
                    if model.cartCleanupFailed { onCartCleanupFailure() }; onCreated(id)
                }
            }
            .onChange(of: model.writeFailure) { _, failure in
                if active, failure == .authenticationRequired { onRequestLogin() }
            }
            .onDisappear { model.stop() }
    }
    private var addressCard: some View {
        Button {
            remarkFocused = false; onChooseAddress(model.addressSelection())
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                if let address = model.address {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                address.value.province + address.value.city + address.value.district
                            ).font(.headline)
                            Text(address.value.address).foregroundStyle(.secondary)
                        }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Text(address.value.contact + "  " + address.value.phone).foregroundStyle(
                            .secondary)
                        Spacer()
                        if address.value.isDefault {
                            Text("默认").font(.caption).foregroundStyle(.white).padding(6)
                                .background(checkoutAccent, in: Capsule()).accessibilityIdentifier(
                                    "checkout.address.default")
                        }
                    }
                } else {
                    Label("请选择收货地址", systemImage: "mappin.and.ellipse")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(model.submitting || model.writeLocked)
            .accessibilityIdentifier("checkout.address")
    }
    @ViewBuilder private var productCards: some View {
        if model.intent.lines.count == 1, let line = model.intent.lines.first {
            productCard(line, index: 0)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(model.intent.lines.enumerated()), id: \.element.id) {
                        index, line in
                        productCard(line, index: index).containerRelativeFrame(.horizontal)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(
                                "checkout.product.\(line.productID).\(line.specificationID)")
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned).scrollIndicators(.hidden)
                .accessibilityIdentifier("checkout.products")
        }
    }
    private func productCard(_ line: BuyNowIntent, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(line.title).font(.headline); Divider()
            HStack(spacing: 12) {
                Group {
                    if let pipeline {
                        RemoteImage(
                            url: line.imageURL, targetSize: CGSize(width: 88, height: 88),
                            contentMode: .fit, pipeline: pipeline, isEnabled: active)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }.frame(width: 88, height: 88).background(
                    .quinary, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 16) {
                    Text(line.specification).font(.subheadline).foregroundStyle(.secondary)
                    let layout =
                        typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout())
                    layout {
                        Text(money(line.unitPriceYuan)).font(.headline).foregroundStyle(
                            .red
                        ).lineLimit(1).minimumScaleFactor(0.5)
                        if !typeSize.isAccessibilitySize { Spacer() }
                        Text("数量：\(line.quantity)").foregroundStyle(.secondary)
                            .accessibilityIdentifier(
                                model.intent.lines.count == 1
                                    ? "checkout.quantity" : "checkout.quantity.\(index)")
                    }
                }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
    private func couponCard(_ coupon: UserCoupon) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "ticket").font(.title2).foregroundStyle(.white).frame(
                    width: 46, height: 46
                )
                .background(checkoutAccent.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 8) {
                    Text(coupon.title).font(.headline)
                    if let end = coupon.endTime {
                        Text("有效期至 " + end).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(money(coupon.amountYuan)).foregroundStyle(.red).font(.title3.bold())
                    Text(coupon.minimumSpendYuan.map { "满\($0)元可用" } ?? "门槛待确认").font(.caption)
                        .foregroundStyle(.secondary)
                }
            }.padding(12)
            Divider()
            HStack {
                Button {
                    if !expanded.insert(coupon.id).inserted { expanded.remove(coupon.id) }
                } label: {
                    Label(
                        "使用说明",
                        systemImage: expanded.contains(coupon.id) ? "chevron.up" : "chevron.down"
                    ).font(.subheadline).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                Spacer()
                Button(
                    presentedSelection == coupon.id
                        ? "已选择" : (model.couponUnavailableReason(coupon) ?? "选择")
                ) {
                    model.toggleCoupon(coupon); showsCoupons = false
                }.padding(.horizontal, 22).padding(.vertical, 10).foregroundStyle(.white)
                    .background(
                        checkoutAccent.opacity(model.canUse(coupon) ? 1 : 0.4), in: Capsule()
                    )
                    .disabled(
                        model.loading
                            || (model.selectedCoupon?.id != coupon.id && !model.canUse(coupon))
                    )
                    .accessibilityHint(presentedSelection == coupon.id ? "再次点按取消选择" : "")
                    .accessibilityIdentifier(
                        "checkout.coupon.\(coupon.id)")
            }.padding(12)
            if expanded.contains(coupon.id) {
                Text(coupon.description).font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(
                        [.horizontal, .bottom], 12)
            }
        }.background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
func money(_ value: Decimal) -> String {
    value.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
}
func sectionTitle(_ text: String) -> some View {
    HStack {
        Capsule().fill(checkoutAccent).frame(width: 4, height: 20); Text(text).font(.headline);
        Spacer()
    }.padding(14)
}
func amountRow(
    _ text: String, symbol: String, value: String, red: Bool = false, stacked: Bool = false
) -> some View {
    let layout =
        stacked
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
    return layout {
        Label(text, systemImage: symbol)
        if !stacked { Spacer() }
        Text(value).foregroundStyle(red ? Color.red : .primary).lineLimit(1).minimumScaleFactor(0.5)
    }.padding(16).accessibilityElement(children: .combine)
}
