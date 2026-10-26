import Foundation
import MallCore
import MallImages
import SwiftUI

@MainActor public struct OrderListEntryView: View {
    private let refreshRevision: UInt64
    private let accountID: Int64
    private let filter: OrderFilter
    private let loader: any OrdersLoading
    private let isActive: Bool
    private let imagePipeline: MallImagePipeline?
    private let onRequestLogin: () -> Void
    private let onOpenOrder: (Int64) -> Void
    public init(
        accountID: Int64, filter: OrderFilter, loader: any OrdersLoading,
        isActive: Bool, imagePipeline: MallImagePipeline?, onRequestLogin: @escaping () -> Void,
        onOpenOrder: @escaping (Int64) -> Void, refreshRevision: UInt64 = 0
    ) {
        self.refreshRevision = refreshRevision
        self.onRequestLogin = onRequestLogin
        self.accountID = accountID; self.filter = filter; self.loader = loader
        self.isActive = isActive; self.imagePipeline = imagePipeline; self.onOpenOrder = onOpenOrder
    }
    public var body: some View {
        OrderListScreen(
            accountID: accountID, filter: filter, loader: loader, isActive: isActive,
            pipeline: imagePipeline, onRequestLogin: onRequestLogin, onOpenOrder: onOpenOrder,
            refreshRevision: refreshRevision
        ).id(accountID)
    }
}
@MainActor private struct OrderListScreen: View {
    let refreshRevision: UInt64
    @State private var seenRevision: UInt64
    @State private var model: OrderListViewModel
    @Environment(\.scenePhase) private var scenePhase
    let isActive: Bool
    let pipeline: MallImagePipeline?
    let onRequestLogin: () -> Void
    let onOpenOrder: (Int64) -> Void
    init(
        accountID: Int64, filter: OrderFilter, loader: any OrdersLoading, isActive: Bool,
        pipeline: MallImagePipeline?, onRequestLogin: @escaping () -> Void,
        onOpenOrder: @escaping (Int64) -> Void, refreshRevision: UInt64
    ) {
        self.refreshRevision = refreshRevision; _seenRevision = State(initialValue: refreshRevision)
        _model = State(
            initialValue: OrderListViewModel(accountID: accountID, filter: filter, loader: loader))
        self.onRequestLogin = onRequestLogin
        self.isActive = isActive; self.pipeline = pipeline; self.onOpenOrder = onOpenOrder
    }
    private func requestLogin() { model.prepareLogin(); onRequestLogin() }
    private struct ReadKey: Equatable {
        let active: Bool; let filter: OrderFilter; let revision: UInt64
    }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(OrderFilter.allCases, id: \.self) { filter in
                        Button(filter.label) { model.select(filter) }
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .foregroundStyle(model.filter == filter ? Color.white : Color.primary)
                            .background(
                                model.filter == filter ? orderAccent : Color.primary.opacity(0.05),
                                in: Capsule()
                            )
                            .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
                            .accessibilityIdentifier("orders.filter.\(filter.rawValue)")
                    }
                }.padding(12)
            }.scrollIndicators(.hidden).accessibilityIdentifier("orders.filters")
            ScrollView {
                LazyVStack(spacing: 16) {
                    if model.state.operation == .initial { ProgressView("正在读取订单") }
                    if let error = model.state.failure {
                        orderError(error, retry: model.retry, login: requestLogin)
                            .accessibilityElement(children: .contain).accessibilityIdentifier(
                                "orders.error")
                    }
                    if model.state.hasLoaded && model.state.items.isEmpty {
                        ContentUnavailableView("暂无订单", systemImage: "list.bullet.rectangle")
                            .accessibilityIdentifier("orders.empty")
                    }
                    ForEach(model.state.items) { order in
                        Button {
                            onOpenOrder(order.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(order.number ?? "订单"); Spacer();
                                    Text(orderStatus(order.status)).foregroundStyle(orderAccent)
                                }
                                Divider()
                                if let lines = order.lines {
                                    ForEach(lines) { line in
                                        OrderLineView(
                                            line: line, pipeline: pipeline, isActive: active)
                                    }
                                } else {
                                    Text("商品信息暂不可用").foregroundStyle(.secondary)
                                }
                                if let date = order.createdAt {
                                    Text(date).font(.footnote).foregroundStyle(.secondary)
                                }
                            }.padding(16).background(
                                .background, in: RoundedRectangle(cornerRadius: 18)
                            )
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("orders.item.\(order.id)")
                    }
                    if let error = model.state.appendFailure {
                        orderError(error, retry: { model.more() }, login: requestLogin)
                            .accessibilityElement(children: .contain).accessibilityIdentifier(
                                "orders.moreError")
                    } else if model.state.nextPage != nil {
                        ProgressView().frame(height: 44).onAppear { model.more(automatic: true) }
                            .onDisappear { model.tailExited() }
                    } else if model.state.hasLoaded && !model.state.items.isEmpty {
                        Text("没有更多了").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(16)
            }.accessibilityIdentifier("orders.list").refreshable { await model.refresh() }
        }
        .background(Color.primary.opacity(0.035)).navigationTitle("我的订单")
        .navigationBarTitleDisplayMode(.inline).tint(orderAccent)
        .task(id: ReadKey(active: active, filter: model.filter, revision: refreshRevision)) {
            await model.activate(active)
            if active, seenRevision != refreshRevision {
                seenRevision = refreshRevision; await model.refresh()
            }
        }
        .onDisappear { model.stop() }
    }
}
let orderAccent = Color(red: 0.29, green: 0.32, blue: 1)
extension OrderFilter {
    var label: String {
        switch self {
        case .all: "全部"
        case .unpaid: "待付款"
        case .unshipped: "待发货"
        case .unreceived: "待收货"
        case .afterSale: "退款/售后"
        case .unevaluated: "待评价"
        case .completed: "已完成"
        }
    }
}
func orderStatus(_ value: Int) -> String {
    switch value {
    case 0: "待付款"
    case 1: "待发货"
    case 2: "待收货"
    case 3: "待评价"
    case 4: "交易完成"
    case 5: "退款中"
    case 6: "已退款"
    case 7: "已关闭"
    default: "状态待确认"
    }
}
@ViewBuilder func orderError(
    _ error: PageReadFailure, retry: @escaping () -> Void, login: @escaping () -> Void
) -> some View {
    VStack(spacing: 12) {
        Text(error == .authenticationRequired ? "请重新登录后查看订单" : "订单读取失败，请重试")
        if error == .authenticationRequired {
            Button("重新登录", action: login).buttonStyle(.bordered).accessibilityIdentifier(
                "orders.login")
        } else {
            Button("重试", action: retry).buttonStyle(.bordered).accessibilityIdentifier(
                "orders.retry")
        }
    }.padding()
}
struct OrderLineView: View {
    let line: OrderLineSnapshot
    let pipeline: MallImagePipeline?
    let isActive: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let pipeline {
                    RemoteImage(
                        url: line.imageURL, targetSize: CGSize(width: 72, height: 72),
                        contentMode: .fit, pipeline: pipeline, isEnabled: isActive)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }.frame(width: 72, height: 72).background(
                .quinary, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(line.title ?? "商品信息暂不可用").foregroundStyle(.primary)
                if let name = line.specification {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
                Text("数量：\(line.quantity)").font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
