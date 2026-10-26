import Foundation
import MallCore
import SwiftUI

@MainActor public struct CouponEntryView: View {
    private let accountID: Int64
    private let loader: any UserCouponsLoading
    private let isActive: Bool
    private let onUse: (Decimal?) -> Void
    private let onRequestLogin: () -> Void
    public init(
        accountID: Int64, loader: any UserCouponsLoading, isActive: Bool,
        onUse: @escaping (Decimal?) -> Void, onRequestLogin: @escaping () -> Void
    ) {
        self.accountID = accountID; self.loader = loader; self.isActive = isActive
        self.onUse = onUse; self.onRequestLogin = onRequestLogin
    }
    public var body: some View {
        CouponScreen(
            accountID: accountID, loader: loader, isActive: isActive,
            onUse: onUse, onRequestLogin: onRequestLogin
        ).id(accountID)
    }
}
@MainActor private struct CouponScreen: View {
    @State private var model: CouponViewModel
    @State private var expanded: Set<Int64> = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    let isActive: Bool
    let onUse: (Decimal?) -> Void
    let onRequestLogin: () -> Void
    init(
        accountID: Int64, loader: any UserCouponsLoading, isActive: Bool,
        onUse: @escaping (Decimal?) -> Void, onRequestLogin: @escaping () -> Void
    ) {
        _model = State(initialValue: CouponViewModel(accountID: accountID, loader: loader))
        self.isActive = isActive; self.onUse = onUse; self.onRequestLogin = onRequestLogin
    }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        VStack(spacing: 0) {
            if let failure = model.state.failure {
                VStack(spacing: 8) {
                    Text(CouponViewModel.message(failure)).foregroundStyle(.red)
                    Button(failure == .authenticationRequired ? "重新登录" : "重试") {
                        if failure == .authenticationRequired {
                            onRequestLogin()
                        } else {
                            model.retry()
                        }
                    }.accessibilityIdentifier("coupons.retry")
                }.padding(12).frame(maxWidth: .infinity).background(.background)
            }
            ScrollView {
                LazyVStack(spacing: 14) {
                    if !model.state.hasLoaded && model.state.operation != nil {
                        ProgressView("正在读取优惠券")
                    }
                    if model.state.hasLoaded && model.state.items.isEmpty {
                        ContentUnavailableView {
                            Label {
                                Text("暂无优惠券").accessibilityIdentifier("coupons.empty")
                            } icon: {
                                Image(systemName: "ticket")
                            }
                        } description: {
                            Text("暂时没有相关内容")
                        } actions: {
                            Button("重新加载") { model.retry() }.accessibilityIdentifier(
                                "coupons.reload")
                        }.padding(.top, 80)
                    }
                    ForEach(model.state.items) { coupon in
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            card(coupon, now: context.date)
                        }
                    }
                    if model.state.nextPage != nil {
                        VStack(spacing: 8) {
                            if let failure = model.state.appendFailure {
                                Text(CouponViewModel.message(failure)).foregroundStyle(.red).font(
                                    .footnote)
                            }
                            if model.state.operation == .append { ProgressView("正在加载") }
                            Button(
                                model.state.appendFailure == .authenticationRequired
                                    ? "重新登录" : model.state.appendFailure == nil ? "加载更多" : "重试加载"
                            ) {
                                if model.state.appendFailure == .authenticationRequired {
                                    onRequestLogin()
                                } else {
                                    model.more()
                                }
                            }
                            .disabled(model.state.operation != nil).accessibilityIdentifier(
                                "coupons.more")
                        }.padding().task { model.more(automatic: true) }.onDisappear {
                            model.tailExited()
                        }
                    } else if model.state.hasLoaded && !model.state.items.isEmpty {
                        Text("没有更多优惠券了").font(.footnote).foregroundStyle(.secondary).padding()
                            .accessibilityIdentifier("coupons.end")
                    }
                }.padding(12).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.always, axes: .vertical).refreshable { await model.refresh() }
            .accessibilityIdentifier("coupons.page")
        }.background(.quinary).navigationTitle("我的优惠券").navigationBarTitleDisplayMode(.inline)
            .task(id: active) { await model.activate(active) }.onDisappear { model.stop() }
    }
    private func card(_ coupon: UserCoupon, now: Date) -> some View {
        let availability = coupon.availability(at: now)
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        heading(coupon); value(coupon)
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "ticket").font(.title2).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(
                                accountAccent.gradient, in: RoundedRectangle(cornerRadius: 12)
                            ).accessibilityHidden(true)
                        heading(coupon); Spacer(minLength: 0); value(coupon)
                    }
                }
            }.padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        rulesButton(coupon)
                        useButton(coupon, availability: availability).frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(alignment: .top) {
                        rulesButton(coupon); Spacer(minLength: 12)
                        useButton(coupon, availability: availability)
                    }
                }
                if expanded.contains(coupon.id) {
                    Text(coupon.description.isEmpty ? "暂无使用说明" : coupon.description)
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(
                            horizontal: false, vertical: true
                        )
                        .accessibilityIdentifier("coupons.description.\(coupon.id)")
                }
            }.padding(16)
        }.background(.background, in: RoundedRectangle(cornerRadius: 18))

    }
    private func rulesButton(_ coupon: UserCoupon) -> some View {
        Button {
            if !expanded.insert(coupon.id).inserted { expanded.remove(coupon.id) }
        } label: {
            Label("使用说明", systemImage: expanded.contains(coupon.id) ? "chevron.up" : "chevron.down")
        }.font(.subheadline).foregroundStyle(.secondary)
            .accessibilityIdentifier("coupons.rules.\(coupon.id)")
            .accessibilityValue(expanded.contains(coupon.id) ? "已展开" : "已收起")
    }
    private func useButton(_ coupon: UserCoupon, availability: CouponAvailability) -> some View {
        Button(availability == .available ? "去使用" : status(availability)) {
            guard coupon.availability() == .available else { return }
            onUse(coupon.minimumSpendYuan)
        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .disabled(availability != .available).accessibilityIdentifier(
                "coupons.use.\(coupon.id)")
    }
    private func heading(_ coupon: UserCoupon) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(coupon.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(coupon.endTime.map { "有效期至 " + $0 } ?? "未提供有效期")
                .font(.caption).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
        }
    }
    private func value(_ coupon: UserCoupon) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                coupon.amountYuan.formatted(
                    .currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
            )
            .font(.title3.bold()).foregroundStyle(.red).fixedSize()
            Text(
                coupon.minimumSpendYuan.map {
                    "满" + NSDecimalNumber(decimal: $0).stringValue + "元可用"
                } ?? "未提供金额门槛"
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func status(_ value: CouponAvailability) -> String {
        switch value {
        case .available: "去使用"
        case .used: "已使用"
        case .expired: "已过期"
        case .disabled: "不可用"
        case .upcoming: "未到使用时间"
        case .unverified: "状态待确认"
        }
    }
}
