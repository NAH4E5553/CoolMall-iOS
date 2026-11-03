import MallCore
import SwiftUI

/// Reads an established order; this entry has no payment capability.
@MainActor public struct CashierEntryView: View {
    private let accountID: Int64
    private let orderID: Int64
    private let loader: any OrdersLoading
    private let isActive: Bool
    private let onBack: () -> Void
    private let onRequestLogin: () -> Void
    public init(
        accountID: Int64, orderID: Int64, loader: any OrdersLoading, isActive: Bool,
        onBack: @escaping () -> Void, onRequestLogin: @escaping () -> Void
    ) {
        self.accountID = accountID; self.orderID = orderID; self.loader = loader
        self.isActive = isActive; self.onBack = onBack; self.onRequestLogin = onRequestLogin
    }
    public var body: some View {
        CashierScreen(
            accountID: accountID, orderID: orderID, loader: loader,
            isActive: isActive, onBack: onBack, onRequestLogin: onRequestLogin
        )
        .id("\(accountID):\(orderID)")
    }
}
@MainActor private struct CashierScreen: View {
    @State private var model: CashierViewModel
    @Environment(\.scenePhase) private var scenePhase
    let isActive: Bool
    let onBack: () -> Void
    let onRequestLogin: () -> Void
    init(
        accountID: Int64, orderID: Int64, loader: any OrdersLoading, isActive: Bool,
        onBack: @escaping () -> Void, onRequestLogin: @escaping () -> Void
    ) {
        _model = State(
            initialValue: CashierViewModel(accountID: accountID, orderID: orderID, loader: loader))
        self.isActive = isActive; self.onBack = onBack; self.onRequestLogin = onRequestLogin
    }
    private struct Key: Equatable { let active: Bool; let attempt: Int }
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                if model.loading { ProgressView("正在读取订单金额") }
                if let order = model.order {
                    if let amounts = order.amounts {
                        Text(money(amounts.payableYuan)).font(.largeTitle.bold()).foregroundStyle(
                            .red
                        )
                        .accessibilityIdentifier("cashier.amount")
                    } else {
                        Text("订单金额暂无法确认").accessibilityIdentifier("cashier.amount.unavailable")
                    }
                    if order.status != 0 { Text("订单状态已变化，请返回详情查看") }
                }
                if let failure = model.failure {
                    Text(failure == .authenticationRequired ? "请重新登录" : "订单读取失败")
                    if failure == .authenticationRequired {
                        Button("重新登录", action: onRequestLogin)
                    }
                }
                if !model.loading, model.failure != nil || model.order?.amounts == nil {
                    Button("重新读取") { model.retry() }.accessibilityIdentifier("cashier.retry")
                }
                VStack(spacing: 0) {
                    Label("支付宝支付", systemImage: "creditcard").frame(
                        maxWidth: .infinity, alignment: .leading
                    ).padding()
                    Divider()
                    Label("微信支付", systemImage: "message").frame(
                        maxWidth: .infinity, alignment: .leading
                    ).padding()
                }.background(.background, in: RoundedRectangle(cornerRadius: 18))
                Text("支付暂未开放，可返回订单详情查看待付款订单。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.padding(20).padding(.top, 36)
        }.background(Color.primary.opacity(0.035)).accessibilityIdentifier("cashier.page")
            .navigationTitle("收银台").navigationBarTitleDisplayMode(.large).tint(checkoutAccent)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("返回订单详情").accessibilityIdentifier("cashier.back")
                }
            }
            .task(id: Key(active: isActive && scenePhase == .active, attempt: model.attempt)) {
                await model.activate(isActive && scenePhase == .active)
            }.onDisappear { model.stop() }
    }
}
