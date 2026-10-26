import Foundation
import MallCore
import MallDesignSystem
import MallImages
import SwiftUI

@MainActor public struct OrderDetailEntryView: View {
    private let accountID: Int64
    private let orderID: Int64
    private let loader: any OrdersLoading
    private let isActive: Bool
    private let onRequestLogin: () -> Void
    private let imagePipeline: MallImagePipeline?
    private let canceller: (any OrderCancelling)?
    private let onCashier: () -> Void
    private let onChanged: () -> Void
    public init(
        accountID: Int64, orderID: Int64, loader: any OrdersLoading,
        isActive: Bool, imagePipeline: MallImagePipeline?, onRequestLogin: @escaping () -> Void,
        canceller: (any OrderCancelling)? = nil, onCashier: @escaping () -> Void = {},
        onChanged: @escaping () -> Void = {}
    ) {
        self.accountID = accountID; self.orderID = orderID; self.loader = loader
        self.isActive = isActive; self.imagePipeline = imagePipeline
        self.onRequestLogin = onRequestLogin; self.canceller = canceller
        self.onCashier = onCashier; self.onChanged = onChanged
    }
    public var body: some View {
        OrderDetailScreen(
            accountID: accountID, orderID: orderID, loader: loader,
            canceller: canceller, isActive: isActive, pipeline: imagePipeline,
            onRequestLogin: onRequestLogin, onCashier: onCashier, onChanged: onChanged
        )
        .id("\(accountID):\(orderID)")
    }
}
@MainActor private struct OrderDetailScreen: View {
    @State private var model: OrderDetailViewModel
    @State private var showsReasons = false
    @Environment(\.scenePhase) private var scenePhase
    let onRequestLogin: () -> Void
    let isActive: Bool
    let pipeline: MallImagePipeline?
    let onCashier: () -> Void
    let onChanged: () -> Void
    init(
        accountID: Int64, orderID: Int64, loader: any OrdersLoading,
        canceller: (any OrderCancelling)?, isActive: Bool, pipeline: MallImagePipeline?,
        onRequestLogin: @escaping () -> Void, onCashier: @escaping () -> Void,
        onChanged: @escaping () -> Void
    ) {
        _model = State(
            initialValue: OrderDetailViewModel(
                accountID: accountID, orderID: orderID,
                loader: loader, canceller: canceller))
        self.onRequestLogin = onRequestLogin; self.isActive = isActive; self.pipeline = pipeline
        self.onCashier = onCashier; self.onChanged = onChanged
    }
    private struct ReadKey: Equatable { let active: Bool; let attempt: Int }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.loading { ProgressView("正在读取订单") }
                    if let failure = model.failure {
                        orderError(
                            failure, retry: model.retry,
                            login: {
                                model.retry(); onRequestLogin()
                            })
                    }
                    if let order = model.order {
                        Text(orderStatus(order.status)).font(.largeTitle.bold())
                            .accessibilityIdentifier("order.status")
                        if let address = order.address {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(address.location).font(.headline); Divider()
                                HStack {
                                    Text(
                                        [address.contact, address.phone].compactMap { $0 }.joined(
                                            separator: "  "))
                                    Spacer()
                                    if address.isDefault == true {
                                        Text("默认").font(.caption).foregroundStyle(.white).padding(6)
                                            .background(orderAccent, in: Capsule())
                                    }
                                }.foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                                .background(.background, in: RoundedRectangle(cornerRadius: 18))
                        }
                        goods(order)
                        VStack(spacing: 0) {
                            heading("价格明细")
                            if let amounts = order.amounts {
                                row("商品总价", value: cash(amounts.subtotalYuan))
                                Divider(); row("优惠金额", value: cash(amounts.discountYuan), red: true)
                                Divider();
                                row(
                                    order.status == 0 ? "应付金额" : "订单金额",
                                    value: cash(amounts.payableYuan))
                            } else {
                                Text("订单金额暂不可用").foregroundStyle(.secondary).padding()
                            }
                        }.background(.background, in: RoundedRectangle(cornerRadius: 18))
                        VStack(spacing: 0) {
                            heading("订单信息")
                            if let number = order.number {
                                HStack {
                                    Text("订单编号"); Spacer();
                                    Text(number).font(.subheadline).foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                }.padding(14); Divider()
                            }
                            if let type = order.payType {
                                row(
                                    "支付方式",
                                    value: type == 1
                                        ? "微信" : type == 2 ? "支付宝" : type == 0 ? "未支付" : "待确认");
                                Divider()
                            }
                            row("支付时间", value: order.paidAt ?? (order.status == 0 ? "未支付" : "未提供"));
                            Divider()
                            if let date = order.createdAt { row("下单时间", value: date); Divider() }
                            row("订单备注", value: order.remark ?? "无")
                            if let reason = order.closeRemark {
                                Divider(); row("关闭原因", value: reason)
                            }
                        }.background(.background, in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityElement(children: .contain).accessibilityIdentifier(
                                "order.info")
                        if model.cancelLocked, order.status == 0 {
                            Text("取消结果正在确认，请刷新订单状态").font(.footnote).foregroundStyle(.secondary)
                            Button("刷新订单状态") { model.retry() }.accessibilityIdentifier(
                                "order.cancel.refresh")
                        }
                    }
                }.padding(12)
            }.accessibilityIdentifier("order.detail").accessibilityHidden(showsReasons)
                .allowsHitTesting(!showsReasons)
            if showsReasons {
                FixedBottomSheet(title: "选择取消原因", onDismiss: { showsReasons = false }) {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if model.reasonsLoading { ProgressView("正在读取取消原因").padding() }
                                if model.reasons?.isEmpty == true { Text("暂无可用取消原因").padding() }
                                ForEach(model.reasons ?? []) { reason in
                                    Button {
                                        model.selectReason(reason)
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(
                                                systemName: model.selectedReason == reason
                                                    ? "largecircle.fill.circle" : "circle"
                                            ).foregroundStyle(
                                                model.selectedReason == reason
                                                    ? orderAccent : .secondary)
                                            Text(reason.name).foregroundStyle(.primary); Spacer()
                                        }.padding(.horizontal, 24).padding(.vertical, 18)
                                            .contentShape(Rectangle())
                                    }.disabled(model.cancelling)
                                        .accessibilityAddTraits(
                                            model.selectedReason == reason ? .isSelected : []
                                        )
                                        .accessibilityIdentifier(
                                            "order.reason.\(reason.id)")
                                }
                                if model.reasons == nil, !model.reasonsLoading {
                                    Button("重新读取") { Task { await model.loadReasons() } }.padding()
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("order.reason.list")
                        Button(model.cancelling ? "正在取消" : "确定") {
                            Task {
                                if await model.cancel() { showsReasons = false; onChanged() }
                            }
                        }.bold().frame(maxWidth: .infinity).padding(16).foregroundStyle(.white)
                            .background(orderAccent, in: Capsule()).padding(16)
                            .disabled(model.selectedReason == nil || !model.canCancel)
                            .accessibilityIdentifier("order.cancel.confirm")
                    }
                }.zIndex(2)
            }
            if let failure = model.cancelFailure {
                Text(failure.message).foregroundStyle(.white).padding(14)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .padding(20)
                    .allowsHitTesting(false).accessibilityIdentifier("order.toast")
                    .task(id: failure) {
                        try? await Task.sleep(for: .seconds(3));
                        if !Task.isCancelled { model.clearCancelFailure() }
                    }
            }

        }.background(Color.primary.opacity(0.035)).tint(orderAccent)
            .navigationTitle(model.order.map { orderStatus($0.status) } ?? "订单详情")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if model.order?.status == 0, !showsReasons {
                    HStack {
                        Spacer()
                        Button("取消订单") {
                            showsReasons = true; Task { await model.loadReasons() }
                        }
                        .disabled(!model.canCancel).accessibilityIdentifier("order.cancel")
                        Button("去支付", action: onCashier).accessibilityIdentifier("order.cashier")
                    }.buttonStyle(.bordered).padding(12).background(.background)
                }
            }
            .refreshable { await model.refresh() }
            .task(id: ReadKey(active: active, attempt: model.attempt)) {
                await model.activate(active)
            }
            .onChange(of: model.cancelFailure) { _, failure in
                if active, failure == .authenticationRequired {
                    showsReasons = false; onRequestLogin()
                }
            }
            .onDisappear { model.stop() }
    }
    @ViewBuilder private func goods(_ order: OrderSnapshot) -> some View {
        if let lines = order.lines, !lines.isEmpty {
            if lines.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(lines) { line in goodsCard(line).containerRelativeFrame(.horizontal)
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.viewAligned).accessibilityIdentifier("order.goods.carousel")
            } else {
                ForEach(lines) { goodsCard($0) }
            }
        } else {
            Text("商品信息暂不可用").foregroundStyle(.secondary).padding()
        }
    }
    private func goodsCard(_ line: OrderLineSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            OrderLineView(line: line, pipeline: pipeline, isActive: active)
            if let price = line.unitPriceYuan {
                Text(cash(price)).font(.headline).foregroundStyle(.red)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
    private func cash(_ value: Decimal) -> String {
        value.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
    }
    private func heading(_ text: String) -> some View {
        HStack {
            Capsule().fill(orderAccent).frame(width: 4, height: 20); Text(text).font(.headline);
            Spacer()
        }.padding(14)
    }
    private func row(_ title: String, value: String, red: Bool = false) -> some View {
        HStack {
            Text(title); Spacer();
            Text(value).font(.subheadline).foregroundStyle(red ? Color.red : .secondary)
        }.padding(14)
    }
}
