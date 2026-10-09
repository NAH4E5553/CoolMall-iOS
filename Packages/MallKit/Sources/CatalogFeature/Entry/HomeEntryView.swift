import MallCore
import MallDesignSystem
import SwiftUI

/// The real home entry for HOME-01's minimal read UI plus HOME-02's section
/// skeleton container: loading, valid-empty, error with an explicit retry, and
/// — on success — the PRD-015 section skeletons followed by the engineering
/// read-verification counts. The App injects the only read capability plus the
/// read-only visibility flag; this view owns no routing and keeps no second
/// copy of results.
///
/// Model lifetime (R-HOME-01-02): the model is created exactly once per
/// Scene/home-root `@State` identity, inside the drive task — tab switches
/// re-evaluate `init`/`body` freely without constructing and discarding
/// replacement models. The single `.task(id:)` key covers visibility AND the
/// retry trigger, so any change cancels the in-flight await (R-HOME-01-01).
@MainActor
public struct HomeEntryView: View {
    @State private var viewModel: HomeViewModel?
    private let home: any HomeLoading
    private let isActive: Bool
    @State private var retryTrigger = 0

    public init(home: any HomeLoading, isActive: Bool) {
        self.home = home
        self.isActive = isActive
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FixtureNoticeView(title: "首页", detail: "首页数据读取已接入，正式栏目布局待接入")
                if let viewModel {
                    switch viewModel.state {
                    case .idle, .loading:
                        ProgressView()
                            .accessibilityIdentifier("home.loading")
                    case .ready(let snapshot):
                        // A dedicated status row carries the loaded marker: a
                        // container-level identifier would override the children's.
                        Text("读取成功")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("home.loaded")
                        // HOME-02: read-only section skeletons; empty sections
                        // hide together with their titles.
                        HomeContentView(snapshot: snapshot)
                        // The H0 seven counts stay observable inside an
                        // explicitly-labeled engineering verification block —
                        // not a seventh business section. A later card must
                        // migrate these assertions before removing it.
                        readVerification(snapshot)
                    case .empty(let snapshot):
                        Text("首页暂无内容")
                            .accessibilityIdentifier("home.empty")
                        // Valid empty still exposes the observable counts,
                        // including the auxiliary full-category number
                        // (R-HOME-01-03); empty semantics and retry stay.
                        counts(snapshot)
                        retryButton
                    case .failed(let failure):
                        VStack(spacing: 4) {
                            Text("首页加载失败，请重试")
                            Text(failureDescription(failure))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("home.error")
                        retryButton
                    }
                } else {
                    // One frame before the drive task creates the model.
                    ProgressView()
                        .accessibilityIdentifier("home.loading")
                }
            }
            // HOME-02 approved layout: 16pt on both sides of the safe-area
            // content; 16pt vertical spacing comes from the container stacks.
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .navigationTitle("首页")
        .task(id: driveKey) { @MainActor in
            if viewModel == nil {
                viewModel = HomeViewModel(home: home)
            }
            await viewModel?.drive(active: isActive, retryToken: retryTrigger)
        }
    }

    private var driveKey: DriveKey {
        DriveKey(active: isActive, retryTrigger: retryTrigger)
    }

    private struct DriveKey: Equatable {
        let active: Bool
        let retryTrigger: Int
    }

    private var retryButton: some View {
        Button("重试") { retryTrigger += 1 }
            .buttonStyle(.borderedProminent)
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
