import MallCore
import MallImages
import MallDesignSystem
import SwiftUI

/// The real home entry: HOME-01's minimal read UI, HOME-02's section
/// skeletons and HOME-02-R1's re-tap behavior — a re-tap of the selected
/// home tab scrolls to the fixed top anchor and offers one refresh. The App
/// injects the only read capability, the read-only visibility flag and the
/// read-only re-tap event; this view owns no routing and keeps no second
/// copy of results.
///
/// Model lifetime (R-HOME-01-02): the model is created exactly once per
/// Scene/home-root `@State` identity, inside the drive task — tab switches
/// re-evaluate `init`/`body` freely without constructing and discarding
/// replacement models. The single `.task(id:)` key covers visibility, the
/// original retry trigger AND the model-ACCEPTED refresh ticket; the RAW
/// re-tap counter never enters the key, so re-taps rejected while busy
/// cannot cancel the active request (H0 v0.3).
@MainActor
public struct HomeEntryView: View {
    @State private var viewModel: HomeViewModel?
    private let home: any HomeLoading
    private let isActive: Bool
    private let refreshRequest: UInt64
    private let imagePipeline: MallImagePipeline?
    @State private var retryTrigger = 0

    public init(
        home: any HomeLoading, isActive: Bool, refreshRequest: UInt64 = 0,
        imagePipeline: MallImagePipeline? = nil
    ) {
        self.home = home
        self.isActive = isActive
        self.refreshRequest = refreshRequest
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // Fixed top anchor for the public re-tap scroll-to-top;
                    // also the observable "scrolled to top" marker.
                    FixtureNoticeView(title: "首页", detail: "首页数据读取已接入，正式栏目布局待接入")
                        .id("home.contentTop")
                        .accessibilityIdentifier("home.contentTop")
                    if let viewModel {
                        switch viewModel.state {
                        case .idle, .loading:
                            loadingFeedback
                        case .ready(let snapshot):
                            // A dedicated status row carries the loaded marker: a
                            // container-level identifier would override the children's.
                            Text("读取成功")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("home.loaded")
                            refreshFeedback
                            // HOME-02: read-only section skeletons; empty sections
                            // hide together with their titles.
                            HomeContentView(
                                snapshot: snapshot, imagePipeline: imagePipeline, isActive: isActive
                            )
                            // The H0 seven counts stay observable inside an
                            // explicitly-labeled engineering verification block —
                            // not a seventh business section.
                            readVerification(snapshot)
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
                            counts(snapshot)
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
            }
            .navigationTitle("首页")
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
                await viewModel?.drive(active: isActive, retryToken: retryTrigger)
            }
        }
    }

    private var driveKey: DriveKey {
        DriveKey(
            active: isActive,
            retryTrigger: retryTrigger,
            // Only the model-ACCEPTED refresh ticket drives the task; raw
            // re-tap tokens that were rejected never change it.
            refreshTicket: viewModel?.refreshTicket ?? 0)
    }

    private struct DriveKey: Equatable {
        let active: Bool
        let retryTrigger: Int
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
        Button("重试") { retryTrigger += 1 }
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
