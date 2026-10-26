import MallCore
import MallImages
import SwiftUI

@MainActor public struct OrderDetailEntryView: View {
    private let accountID: Int64
    private let orderID: Int64
    private let loader: any OrdersLoading
    private let isActive: Bool
    private let onRequestLogin: () -> Void
    private let imagePipeline: MallImagePipeline?
    public init(
        accountID: Int64, orderID: Int64, loader: any OrdersLoading,
        isActive: Bool, imagePipeline: MallImagePipeline?, onRequestLogin: @escaping () -> Void
    ) {
        self.onRequestLogin = onRequestLogin
        self.accountID = accountID; self.orderID = orderID; self.loader = loader
        self.isActive = isActive; self.imagePipeline = imagePipeline
    }
    public var body: some View {
        OrderDetailScreen(
            accountID: accountID, orderID: orderID, loader: loader,
            isActive: isActive, pipeline: imagePipeline, onRequestLogin: onRequestLogin
        ).id("\(accountID):\(orderID)")
    }
}
@MainActor private struct OrderDetailScreen: View {
    @State private var model: OrderDetailViewModel
    @Environment(\.scenePhase) private var scenePhase
    let onRequestLogin: () -> Void
    let isActive: Bool
    let pipeline: MallImagePipeline?
    init(
        accountID: Int64, orderID: Int64, loader: any OrdersLoading,
        isActive: Bool, pipeline: MallImagePipeline?, onRequestLogin: @escaping () -> Void
    ) {
        _model = State(
            initialValue: OrderDetailViewModel(
                accountID: accountID, orderID: orderID, loader: loader))
        self.onRequestLogin = onRequestLogin
        self.isActive = isActive; self.pipeline = pipeline
    }
    private struct ReadKey: Equatable { let active: Bool; let attempt: Int }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.loading { ProgressView("正在读取订单") }
                if let failure = model.failure {
                    orderError(
                        failure, retry: model.retry,
                        login: {
                            model.retry(); onRequestLogin()
                        })
                }
                if let order = model.order {
                    Text(orderStatus(order.status)).font(.title2.bold()).foregroundStyle(
                        orderAccent
                    )
                    .accessibilityIdentifier("order.status")
                    if let address = order.address {
                        VStack(alignment: .leading, spacing: 8) {
                            if let contact = address.contact { Text(contact) }
                            if let phone = address.phone { Text(phone) }
                            if !address.location.isEmpty { Text(address.location) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding()
                            .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        if let lines = order.lines {
                            ForEach(lines) { line in
                                OrderLineView(line: line, pipeline: pipeline, isActive: active)
                            }
                        } else {
                            Text("商品信息暂不可用").foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 12) {
                        if let number = order.number { LabeledContent("订单号", value: number) }
                        if let date = order.createdAt { LabeledContent("创建时间", value: date) }
                        if let date = order.paidAt { LabeledContent("支付时间", value: date) }
                    }.padding().background(.background, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityIdentifier("order.info")
                }
            }.padding(16)
        }.accessibilityIdentifier("order.detail").background(Color.primary.opacity(0.035))
            .navigationTitle("订单详情").navigationBarTitleDisplayMode(.inline).tint(orderAccent)
            .refreshable { await model.refresh() }
            .task(id: ReadKey(active: active, attempt: model.attempt)) {
                await model.activate(active)
            }
            .onDisappear { model.stop() }
    }
}
