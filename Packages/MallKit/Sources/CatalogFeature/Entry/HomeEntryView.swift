import MallCore
import MallImages
import MallDesignSystem
import SwiftUI

/// Scene/home-root entry over one internal model. The App supplies the
/// read capability, visibility, images, test-only read markers and actions.
/// Re-tap and pull refresh share a synchronously reserved ticket; the single
/// drive task performs every accepted request, and a pull waits for its own
/// ticket to finish. Busy events cannot change the task key or queue a read.
@MainActor
public struct HomeEntryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: HomeViewModel?
    @GestureState private var isPullDragging = false
    @State private var pullInteraction: UInt64 = 0
    @State private var bannerViewport = CGRect.zero
    private let home: any HomeLoading
    private let isActive: Bool
    private let allowsBannerAutoplay: Bool
    private let refreshRequest: UInt64
    private let imagePipeline: MallImagePipeline?
    private let showsReadVerification: Bool
    private let onUnavailableAction: () -> Void
    private let onOpenProduct: ((Int64) -> Void)?
    private let onReceiveCoupons: (([CouponClaimOffer]) -> Void)?

    public init(
        home: any HomeLoading, isActive: Bool, refreshRequest: UInt64 = 0,
        imagePipeline: MallImagePipeline? = nil,
        allowsBannerAutoplay: Bool = true,
        showsReadVerification: Bool = false, onUnavailableAction: @escaping () -> Void = {},
        onOpenProduct: ((Int64) -> Void)? = nil,
        onReceiveCoupons: (([CouponClaimOffer]) -> Void)? = nil
    ) {
        self.home = home
        self.isActive = isActive
        self.allowsBannerAutoplay = allowsBannerAutoplay
        self.refreshRequest = refreshRequest
        self.imagePipeline = imagePipeline
        self.showsReadVerification = showsReadVerification
        self.onUnavailableAction = onUnavailableAction
        self.onOpenProduct = onOpenProduct
        self.onReceiveCoupons = onReceiveCoupons
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // Leaf AX marker; the scroll target is the complete padded
                    // content container below, so manual and native re-taps
                    // use the same outer content edge.
                    Color.clear.frame(height: 1)
                        .accessibilityIdentifier("home.contentTop")
                    if let viewModel {
                        switch viewModel.state {
                        case .idle, .loading:
                            loadingFeedback
                        case .ready(let snapshot):
                            // A dedicated status row carries the loaded marker: a
                            // container-level identifier would override the children's.
                            if showsReadVerification {
                                Text("读取成功")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("home.loaded")
                            }
                            refreshFeedback
                            // Read-only sections hide with their own empty arrays.
                            HomeContentView(
                                snapshot: snapshot, imagePipeline: imagePipeline,
                                isActive: isActive, allowsBannerAutoplay: allowsBannerAutoplay,
                                bannerViewport: bannerViewport, isUserDragging: isPullDragging,
                                onUnavailableAction: onUnavailableAction,
                                onOpenProduct: onOpenProduct, onReceiveCoupons: onReceiveCoupons
                            )

                            // The H0 seven counts stay observable inside an
                            // explicitly-labeled engineering verification block —
                            // not a seventh business section.
                            if showsReadVerification { readVerification(snapshot) }
                        case .empty(let snapshot):
                            VStack(spacing: 16) {
                                statusMessage("首页暂无内容", id: "home.empty")
                                retryButton(disabled: viewModel.isRefreshing)
                            }
                            .padding(.vertical, 16)
                            refreshFeedback
                            // Valid empty still exposes the observable counts,
                            // including the auxiliary full-category number
                            // (R-HOME-01-03); empty semantics and retry stay.
                            if showsReadVerification { counts(snapshot) }
                        case .failed(let failure):
                            VStack(spacing: 16) {
                                statusMessage(
                                    "首页加载失败，请重试", detail: failureDescription(failure),
                                    id: "home.error")
                                retryButton(disabled: false)
                            }
                            .padding(.vertical, 16)
                        }
                    } else {
                        // One frame before the drive task creates the model.
                        loadingFeedback
                    }
                }
                // HOME-02 approved layout: 16pt on both sides of the safe-area
                // content; 16pt vertical spacing comes from the container stacks.
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .id("home.contentTop")
            }
            .accessibilityIdentifier("home.scroll")
            // The onscreen banner region: the scroll viewport minus its
            // safe-area insets (top chrome, tab bar, DEBUG control strip).
            .onGeometryChange(for: CGRect.self) { geometry in
                let frame = geometry.frame(in: .global)
                let insets = geometry.safeAreaInsets
                return CGRect(
                    x: frame.minX + insets.leading, y: frame.minY + insets.top,
                    width: max(0, frame.width - insets.leading - insets.trailing),
                    height: max(0, frame.height - insets.top - insets.bottom))
            } action: {
                bannerViewport = $0
            }
            // Keep the viewport across visibility transactions; ordinary
            // content updates retain SwiftUI's default offset adjustment.
            .transaction(value: isActive) { transaction in
                if #available(iOS 18.0, *) {
                    transaction.scrollContentOffsetAdjustmentBehavior = .disabled
                }
            }
            .background(Color(white: colorScheme == .dark ? 0.06 : 0.95))
            .simultaneousGesture(
                DragGesture(minimumDistance: 1).updating($isPullDragging) { _, dragging, _ in
                    dragging = true
                }
            )
            .onChange(of: isPullDragging) { _, dragging in
                if dragging { pullInteraction &+= 1 }
            }
            .refreshable {
                await viewModel?.pullToRefresh(interaction: pullInteraction)
            }
            .accessibilityAction(named: "刷新") { viewModel?.requestAccessibleRefresh() }
            .onChange(of: refreshRequest) { _, _ in
                // A real home re-tap (App-verified event): always scroll to the
                // fixed top anchor through the public API, then OFFER the
                // refresh — the model may reject it (busy / nothing to show)
                // without any task-key change.
                proxy.scrollTo("home.contentTop", anchor: .top)
                viewModel?.requestRefresh(refreshRequest)
            }
            .task(id: driveKey) { @MainActor in
                if viewModel == nil {
                    viewModel = HomeViewModel(home: home)
                }
                await viewModel?.drive(active: isActive, retryToken: 0)
            }
            // R-OWN-01-LIFE: once the first read finishes, this view's
            // `.task` has RETURNED — a re-tap's 300ms merge timer and any
            // in-flight refresh are owned only by the view model's single
            // owner task afterwards, so SwiftUI cancelling this (already
            // finished) task cannot reach them. `onDisappear` is the
            // reliable teardown hook for view removal / scene end: it makes
            // the owner invalidate the current intent, cancel the timer and
            // the in-flight read, end pull waiters and clear this page's
            // pending/busy/loading state — without assuming any later
            // `drive(active:false)` will run. Duplicate notifications (the
            // `isActive=false` path fires the same cleanup) are idempotent.
            .onDisappear {
                viewModel?.pageTeardown()
            }
        }
    }

    private var driveKey: DriveKey {
        DriveKey(
            active: isActive,
            // Only the model-ACCEPTED refresh ticket drives the task; raw
            // re-tap tokens that were rejected never change it.
            refreshTicket: viewModel?.refreshTicket ?? 0)
    }

    private struct DriveKey: Equatable {
        let active: Bool
        let refreshTicket: UInt64
    }

    /// HOME-03 feedback is a read-only projection. Actions still use the
    /// original drive/retry entries; these views own no request state.
    private var loadingFeedback: some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityIdentifier("home.loading")
            statusMessage("正在加载首页", id: "home.loading.message")
        }
        .padding(.vertical, 16)
    }

    private func statusMessage(_ title: String, detail: String? = nil, id: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityIdentifier(id)
            if let detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(id).reason")
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// Refresh feedback stays above the retained snapshot. The vertical
    /// failure layout lets the recovery button stay readable at large sizes.
    @ViewBuilder
    private var refreshFeedback: some View {
        if let viewModel {
            if viewModel.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    // Identifiers sit on the leaf texts: a container-level
                    // identifier would override the children's.
                    Text("正在刷新")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("home.refreshing")
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if viewModel.refreshFailedHint {
                VStack(spacing: 8) {
                    Text("刷新失败，请重试")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home.refresh.failed")
                    Button("重试") {
                        viewModel.requestRetryRefresh()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRefreshing)
                    .accessibilityIdentifier("home.refresh.retry")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func retryButton(disabled: Bool) -> some View {
        Button("重试") { viewModel?.requestUserRetry() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(disabled)
            .accessibilityIdentifier("home.retry")
    }

    /// Engineering-period read verification: the H0 seven counts (PRD-015
    /// order, auxiliary full-category last) remain observable without being a
    /// home content section.
    private func readVerification(_ snapshot: HomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("读取校验（工程期）")
                .font(.footnote)
                .foregroundStyle(.secondary)
            counts(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func counts(_ snapshot: HomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            countRow("轮播", snapshot.banners.count, id: "banner")
            countRow("优惠券", snapshot.coupons.count, id: "coupon")
            countRow("分类", snapshot.categories.count, id: "category")
            countRow("限时精选", snapshot.featured.count, id: "flashSale")
            countRow("推荐", snapshot.recommendations.count, id: "recommend")
            countRow("全部商品", snapshot.goods.count, id: "goods")
            countRow("完整分类（辅助）", snapshot.allCategories.count, id: "categoryAll")
        }
    }

    private func countRow(_ label: String, _ count: Int, id: String) -> some View {
        Text(verbatim: "\(label)：\(count)")
            .accessibilityIdentifier("home.count.\(id)")
    }

    private func failureDescription(_ failure: HomeLoadFailure) -> String {
        switch failure {
        case .networkUnavailable: "网络不可用"
        case .timeout: "请求超时"
        case .httpStatus(let code): "服务错误（\(code)）"
        case .businessCode(let code): "业务失败（\(code)）"
        case .invalidConfiguration: "配置错误"
        case .invalidResponse: "响应无效"
        case .invalidPayload: "数据无效"
        }
    }
}
