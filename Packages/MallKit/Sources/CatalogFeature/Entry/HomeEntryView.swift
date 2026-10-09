import MallCore
import MallDesignSystem
import SwiftUI

/// The real home entry for HOME-01's minimal read UI: loading, valid-empty,
/// error with an explicit retry, and section counts on success. The App
/// injects the only read capability plus the read-only visibility flag; this
/// view owns no routing and keeps no second copy of results.
@MainActor
public struct HomeEntryView: View {
    @State private var viewModel: HomeViewModel
    private let isActive: Bool
    @State private var retryTrigger = 0

    public init(home: any HomeLoading, isActive: Bool) {
        _viewModel = State(initialValue: HomeViewModel(home: home))
        self.isActive = isActive
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FixtureNoticeView(title: "首页", detail: "首页数据读取已接入，正式栏目布局待接入")
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
                    counts(snapshot)
                case .empty:
                    Text("首页暂无内容")
                        .accessibilityIdentifier("home.empty")
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
            }
            .padding()
        }
        .navigationTitle("首页")
        .task(id: isActive) {
            await viewModel.handleVisibility(isActive)
        }
        .task(id: retryTrigger) {
            guard retryTrigger > 0 else { return }
            await viewModel.retry()
        }
    }

    private var retryButton: some View {
        Button("重试") { retryTrigger += 1 }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("home.retry")
    }

    /// PRD-015 order: 轮播 / 优惠券 / 分类 / 限时精选 / 推荐 / 全部商品,
    /// with the full-category count as a separate auxiliary line.
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
