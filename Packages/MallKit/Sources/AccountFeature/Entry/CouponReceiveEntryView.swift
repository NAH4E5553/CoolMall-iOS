import Foundation
import MallCore
import SwiftUI

/// The presentation owns all per-coupon request models until dismissal, including offscreen rows.
@MainActor public struct CouponReceiveEntryView: View {
    @State private var models: [Int64: CouponReceiveViewModel]
    @State private var loginCouponID: Int64?
    @State private var toast: CouponReceiveViewModel.Feedback?
    @GestureState private var dragOffset: CGFloat = 0
    @State private var expanded: Set<Int64> = []
    @State private var rowHeights: [Int64: CGFloat] = [:]
    @State private var headerHeight: CGFloat = 68
    @ScaledMetric private var estimatedRowHeight: CGFloat = 148
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    private let offers: [CouponClaimOffer]
    private let state: AccountState
    private let session: any AccountSession
    private let challenges: any LoginChallenges
    private let notifier: any VerificationCodeDelivering
    private let onDismiss: () -> Void
    public init(
        offers: [CouponClaimOffer], state: AccountState, receiver: any CouponReceiving,
        session: any AccountSession, challenges: any LoginChallenges,
        notifier: any VerificationCodeDelivering, onDismiss: @escaping () -> Void
    ) {
        self.offers = offers; self.state = state; self.session = session;
        self.challenges = challenges
        self.notifier = notifier; self.onDismiss = onDismiss
        _models = State(
            initialValue: Dictionary(
                offers.map { ($0.id, CouponReceiveViewModel(couponID: $0.id, receiver: receiver)) },
                uniquingKeysWith: { first, _ in first }))
    }
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.32).ignoresSafeArea()
                    .contentShape(Rectangle()).onTapGesture(perform: onDismiss)
                    .accessibilityLabel("关闭优惠券弹框").accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("couponClaim.dismiss")
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Capsule().fill(.tertiary).frame(width: 40, height: 4).padding(.top, 12)
                        Text("领取优惠券").font(.headline).padding(.vertical, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("couponClaim.dragHandle")
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .updating($dragOffset) { value, offset, _ in
                                if value.translation.height > abs(value.translation.width) {
                                    offset = max(0, value.translation.height)
                                }
                            }
                            .onEnded { value in
                                if value.translation.height >= 64
                                    && value.translation.height > abs(value.translation.width) * 1.3
                                {
                                    onDismiss()
                                }
                            }
                    )
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        headerHeight = $0
                    }
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(offers) { offer in
                                if let model = models[offer.id] {
                                    card(offer, model: model)
                                        .onGeometryChange(for: CGFloat.self) {
                                            $0.size.height
                                        } action: {
                                            rowHeights[offer.id] = $0
                                        }
                                }
                            }
                        }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
                    }.accessibilityIdentifier("couponClaim.list")
                        .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.bottom, max(16, geometry.safeAreaInsets.bottom))
                .frame(height: preferredHeight(in: geometry))
                .frame(maxWidth: 760)
                .background(
                    .quinary,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 24, topTrailingRadius: 24)
                )
                .background(
                    .background,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 24, topTrailingRadius: 24)
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("couponClaim.panel")
                .offset(y: dragOffset)
                if let toast {
                    VStack {
                        Spacer()
                        Text(toast.message).font(.subheadline).multilineTextAlignment(.center)
                            .padding(.horizontal, 20).padding(.vertical, 14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 8, y: 3)
                            .accessibilityIdentifier("couponClaim.toast")
                            .accessibilityAddTraits(.updatesFrequently)
                        Spacer()
                    }.frame(maxWidth: 460).padding(.horizontal, 24).allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .tint(accountAccent)
        .accessibilityAction(.escape, onDismiss)
        .sheet(
            isPresented: Binding(
                get: { loginCouponID != nil }, set: { if !$0 { loginCouponID = nil } })
        ) {
            NavigationStack {
                LoginEntryView(
                    session: session, challenges: challenges, notifier: notifier,
                    isActive: loginCouponID != nil && scenePhase != .background,
                    onAuthenticated: {
                        if let id = loginCouponID { models[id]?.authenticationCompleted() }
                        loginCouponID = nil
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("返回") { loginCouponID = nil }
                    }
                }
            }
        }
        .task(id: toast?.id) {
            guard let id = toast?.id else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            if toast?.id == id { toast = nil }
        }
        .onChange(of: state.profile?.id, initial: true) { _, id in
            toast = nil
            for model in models.values { model.setAccount(id) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopWaiting() } }
        .onDisappear { stopWaiting() }
    }
    private func preferredHeight(in geometry: GeometryProxy) -> CGFloat {
        // Only the viewport uses three rows. The scroll always contains every returned offer.
        let firstRows = offers.prefix(3)
        let rows = firstRows.reduce(CGFloat.zero) { $0 + (rowHeights[$1.id] ?? estimatedRowHeight) }
        let gaps = CGFloat(max(0, firstRows.count - 1)) * 12
        return min(
            geometry.size.height * 0.76,
            headerHeight + rows + gaps + 20 + max(16, geometry.safeAreaInsets.bottom))
    }
    private func stopWaiting() {
        toast = nil
        for model in models.values { model.stopWaiting() }
    }
    private func card(_ offer: CouponClaimOffer, model: CouponReceiveViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        heading(offer); value(offer)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "ticket").font(.title2).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                accountAccent.gradient, in: RoundedRectangle(cornerRadius: 10)
                            )
                            .accessibilityHidden(true)
                        heading(offer).frame(maxWidth: .infinity, alignment: .leading)
                        value(offer)
                    }
                }
            }.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        rulesButton(offer); actions(offer, model: model)
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        rulesButton(offer); Spacer(minLength: 0); actions(offer, model: model)
                    }
                }
                if expanded.contains(offer.id) {
                    Text(offer.description.isEmpty ? "暂无使用说明" : offer.description)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("couponClaim.description.\(offer.id)")
                }
            }.padding(12)
        }.background(.background, in: RoundedRectangle(cornerRadius: 16))
            .onChange(of: model.feedback?.id) { _, _ in
                if let feedback = model.feedback { toast = feedback }
            }
    }
    private func heading(_ offer: CouponClaimOffer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(offer.title).font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("couponClaim.title.\(offer.id)")
            Text(offer.endTime.map { "有效期至 " + $0 } ?? "未提供有效期")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("couponClaim.expiry.\(offer.id)")
        }
    }
    private func value(_ offer: CouponClaimOffer) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let amount = offer.amountYuan {
                Text(amount.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN"))))
                    .font(.title3.bold()).foregroundStyle(.red).fixedSize()
                    .accessibilityIdentifier("couponClaim.amount.\(offer.id)")
            }
            Text(
                offer.minimumSpendYuan.map {
                    $0 == 0 ? "无门槛" : "满" + NSDecimalNumber(decimal: $0).stringValue + "元可用"
                } ?? "未提供金额门槛"
            )
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("couponClaim.minimum.\(offer.id)")
        }
    }
    private func rulesButton(_ offer: CouponClaimOffer) -> some View {
        Button {
            if !expanded.insert(offer.id).inserted { expanded.remove(offer.id) }
        } label: {
            Label("使用说明", systemImage: expanded.contains(offer.id) ? "chevron.up" : "chevron.down")
        }.font(.caption).foregroundStyle(.secondary)
            .accessibilityValue(expanded.contains(offer.id) ? "已展开" : "已收起")
            .accessibilityIdentifier("couponClaim.rules.\(offer.id)")
    }
    private func actions(_ offer: CouponClaimOffer, model: CouponReceiveViewModel) -> some View {
        claimButton(offer, model: model)
    }
    private func claimButton(_ offer: CouponClaimOffer, model: CouponReceiveViewModel) -> some View
    {
        Button {
            toast = nil
            if state.profile == nil || model.phase == .failed(.authenticationRequired) {
                loginCouponID = offer.id
            } else {
                model.claim()
            }
        } label: {
            Text("立即领取").padding(.leading, 18)
                .overlay(alignment: .leading) {
                    if model.busy { ProgressView().tint(.white).controlSize(.mini) }
                }
        }.font(.subheadline.weight(.semibold)).buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule).disabled(model.busy)
            .accessibilityLabel("立即领取")
            .accessibilityValue(buttonStatus(model.phase))
            .accessibilityIdentifier("couponClaim.confirm.\(offer.id)")
    }
    private func buttonStatus(_ phase: CouponReceiveViewModel.Phase) -> String {
        switch phase {
        case .submitting: "正在领取"
        case .received: "已领取"
        case .unconfirmed: "结果待核对"
        default: ""
        }
    }
}

#if DEBUG
    private struct CouponOfferPreviewServices: AccountSession, LoginChallenges,
        VerificationCodeDelivering, CouponReceiving
    {
        var initialState: AccountState { .guest }
        func states() async -> AsyncStream<AccountState> { AsyncStream { $0.finish() } }
        func login(_ credential: LoginCredential) async throws { throw AccountFailure.invalidInput }
        func logout() async throws {}
        func refreshProfile() async throws {}
        func captcha() async throws -> LoginCaptcha { throw AccountFailure.invalidConfiguration }
        func requestCode(phone: String, captchaID: String, answer: String) async throws -> String {
            throw AccountFailure.invalidConfiguration
        }
        func prepare() async throws { throw AccountFailure.notificationsDenied }
        func deliver(_ code: String) async throws { throw AccountFailure.notificationDelivery }
        func receiveCoupon(accountID: Int64, couponID: Int64) async throws -> String? {
            throw CouponClaimFailure.invalidConfiguration
        }
    }
    @MainActor private struct CouponOffersPreview: View {
        var count = 3
        private let services = CouponOfferPreviewServices()
        var body: some View {
            CouponReceiveEntryView(
                offers: (1...count).map { index in
                    CouponClaimOffer(
                        id: Int64(index), title: "【满减券】预览商品满299减30元",
                        description: "预览商品使用说明", amountYuan: 30, minimumSpendYuan: 299,
                        endTime: "2030-01-01 00:00:00")
                }, state: .guest, receiver: services,
                session: services, challenges: services, notifier: services,
                onDismiss: {})
        }
    }
    #Preview("三张券") { CouponOffersPreview() }
    #Preview("更多券与大字号") { CouponOffersPreview(count: 7).dynamicTypeSize(.accessibility5) }
    #Preview("深色") { CouponOffersPreview().preferredColorScheme(.dark) }
#endif
