import SwiftUI

/// First-load feedback (reference `PageLoading`): a centered spinner plus the
/// 12sp body-medium "加载中..." label, 8pt apart.
struct CategoryLoadingView: View {
    let palette: CategoryPalette
    @ScaledMetric(relativeTo: .caption) private var messageSize = 12.0

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
                .tint(palette.onSurface)
                .accessibilityIdentifier("category.loading")
            Text("加载中...")
                .font(.system(size: messageSize))
                .foregroundStyle(palette.onSurface)
                .accessibilityIdentifier("category.loading.message")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Successful but empty tree (reference `Empty` with `category_empty`): the
/// reference empty state has no retry action and no subtitle.
struct CategoryEmptyView: View {
    let palette: CategoryPalette
    @ScaledMetric(relativeTo: .headline) private var titleSize = 16.0

    var body: some View {
        VStack(spacing: 0) {
            CategoryStateIcon(systemName: "tray", palette: palette)
            Color.clear.frame(height: CategoryMetrics.stateTitleSpacing)
            Text("暂无分类")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("category.empty")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CategoryMetrics.statePadding)
    }
}

/// Failure with retry (reference `EmptyNetwork`): generic network wording, the
/// reference does not surface raw codes or backend messages; the outlined retry
/// button keeps the 0.5pt primary border and bounded width.
struct CategoryErrorView: View {
    let palette: CategoryPalette
    let onRetry: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize = 16.0
    @ScaledMetric(relativeTo: .caption) private var subtitleSize = 12.0
    @ScaledMetric(relativeTo: .caption) private var retryLabelSize = 12.0

    var body: some View {
        VStack(spacing: 0) {
            CategoryStateIcon(systemName: "wifi.exclamationmark", palette: palette)
            Color.clear.frame(height: CategoryMetrics.stateTitleSpacing)
            Text("网络连接失败")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("category.error")
            Color.clear.frame(height: CategoryMetrics.stateSubtitleSpacing)
            Text("请检查网络连接后重试")
                .font(.system(size: subtitleSize))
                .foregroundStyle(palette.tertiary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("category.error.detail")
            Color.clear.frame(height: CategoryMetrics.stateRetrySpacing)
            // Reference OutlinedButton: CornerFull shape, explicit 0.5dp
            // primary BorderStroke, 200dp minimum width, 40dp minimum height,
            // 24dp content padding and M3 1.4 outlined label color
            // (onSurfaceVariant). The system .bordered style cannot express the
            // explicit 0.5pt outline contract.
            Button(action: onRetry) {
                Text("重新加载")
                    .font(.system(size: retryLabelSize))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, CategoryMetrics.retryContentHorizontalPadding)
                    .frame(
                        minWidth: CategoryMetrics.retryMinWidth,
                        maxWidth: CategoryMetrics.retryMaxWidth,
                        minHeight: CategoryMetrics.retryMinHeight
                    )
                    .overlay {
                        Capsule().stroke(
                            palette.primary, lineWidth: CategoryMetrics.retryBorderWidth)
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, CategoryMetrics.retryHorizontalPadding)
            .accessibilityIdentifier("category.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CategoryMetrics.statePadding)
    }
}

/// Reference empty icons are 120dp illustrations tinted with 20% onSurface;
/// the SF Symbol is the closest system glyph and keeps the same reserved area
/// (the mapping is recorded in PRODUCT_SPEC, not claimed pixel-equal).
private struct CategoryStateIcon: View {
    let systemName: String
    let palette: CategoryPalette

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: CategoryMetrics.stateIconPointSize))
            .foregroundStyle(palette.onSurface.opacity(0.2))
            .frame(width: CategoryMetrics.stateIconArea, height: CategoryMetrics.stateIconArea)
            .accessibilityHidden(true)
    }
}

/// DEBUG read-verification marker for controlled fixtures; not a product row
/// and never present in Release (the App only enables it for fixture launches).
struct CategoryVerificationBar: View {
    let snapshot: CategorySnapshot
    let selectedRootID: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("读取成功").accessibilityIdentifier("category.loaded")
            Text(verbatim: "一级分类：\(snapshot.rootCount)")
                .accessibilityIdentifier("category.count.roots")
            Text(verbatim: "直接子分类：\(snapshot.directChildCount)")
                .accessibilityIdentifier("category.count.children")
            Text(verbatim: "选中：\(selectedRootID.map { String($0) } ?? "无")")
                .accessibilityIdentifier("category.selected")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
