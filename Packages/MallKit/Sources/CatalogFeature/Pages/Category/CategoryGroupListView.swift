import MallCore
import MallImages
import SwiftUI

/// Right pane: one scrolling group per root, 24pt apart, 16pt top inset and
/// 8pt horizontal inset. Each group shows the reference `TitleWithLine`
/// (4x20 primary bar, 8pt gap, 14sp bold onSurface) and, when it has direct
/// children, a 3-column grid of square images + 11sp centered names.
///
/// Scroll linkage: the first group whose frame still intersects the viewport
/// drives the left selection (the reference uses `firstVisibleItemIndex`).
/// While a left-tap scroll is pending, the model ignores intermediate frames;
/// a real drag clears that guard. The bottom content margin reproduces the
/// reference `maxHeight - 80` padding so even the last short group can reach the
/// top and become the selected one.
struct CategoryGroupListView: View {
    let snapshot: CategorySnapshot
    let scrollRequest: CategoryViewModel.ScrollRequest?
    let palette: CategoryPalette
    let imagePipeline: MallImagePipeline?
    let isActive: Bool
    let onScrollSelection: (Int64) -> Void
    let onUserDrag: () -> Void
    let onOpenSubcategory: (Int64) -> Void

    /// Reference cache for the at-top check only. Mutations must NOT be view
    /// state: updating SwiftUI state on every scroll frame interrupts the
    /// in-flight programmatic scroll animation.
    @State private var frameCache = CategoryFrameCache()

    private static let spaceName = "category.right.viewport"

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: CategoryMetrics.groupSpacing) {
                        ForEach(snapshot.groups) { group in
                            CategoryGroupSection(
                                group: group,
                                imageSide: imageSide(for: geometry.size.width),
                                palette: palette,
                                imagePipeline: imagePipeline,
                                isActive: isActive,
                                onOpenSubcategory: onOpenSubcategory
                            )
                            .id(group.root.id)
                            .background(frameReader(for: group.root.id))
                        }
                    }
                    .padding(.top, CategoryMetrics.rightTopPadding)
                    .padding(.horizontal, CategoryMetrics.rightHorizontalPadding)
                }
                .contentMargins(
                    .bottom, bottomMargin(for: geometry.size.height), for: .scrollContent
                )
                .background(palette.surface)
                .coordinateSpace(name: Self.spaceName)
                .accessibilityIdentifier("category.right.scroll")
                .onPreferenceChange(CategoryGroupFrameKey.self) { frames in
                    frameCache.frames = frames
                    guard let firstVisible = firstVisibleGroupID(in: frames) else { return }
                    onScrollSelection(firstVisible)
                }
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    // Only a group genuinely at the top may skip the scroll:
                    // minY == 0 after scrolling, or the first group's 16pt top
                    // inset at the very beginning. A negative minY means the
                    // group is ABOVE the viewport and must be scrolled back to
                    // the top (R-CATEGORY-01-01).
                    let isFirstGroup = snapshot.groups.first?.root.id == request.rootID
                    if let frame = frameCache.frames[request.rootID],
                        abs(frame.minY) <= 1
                            || (isFirstGroup
                                && abs(frame.minY - CategoryMetrics.rightTopPadding) <= 1)
                    {
                        onScrollSelection(request.rootID)
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(request.rootID, anchor: .top)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1).onChanged { _ in onUserDrag() }
                )
            }
        }
    }

    private func frameReader(for id: Int64) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CategoryGroupFrameKey.self,
                value: [id: proxy.frame(in: .named(Self.spaceName))]
            )
        }
    }

    private func firstVisibleGroupID(in frames: [Int64: CGRect]) -> Int64? {
        snapshot.groups.first { group in
            guard let frame = frames[group.root.id] else { return false }
            return frame.maxY > 1
        }?.root.id
    }

    private func imageSide(for panelWidth: CGFloat) -> CGFloat {
        // Panel width - 2*8 horizontal padding - 3 columns*2*8 item padding.
        let side =
            (panelWidth - 2 * CategoryMetrics.rightHorizontalPadding
                - 3 * 2 * CategoryMetrics.subItemPadding) / CGFloat(CategoryMetrics.gridColumnCount)
        return max(1, side)
    }

    private func bottomMargin(for viewportHeight: CGFloat) -> CGFloat {
        max(
            viewportHeight - CategoryMetrics.bottomPaddingReserve,
            CategoryMetrics.bottomPaddingFloor)
    }
}

private final class CategoryFrameCache {
    var frames: [Int64: CGRect] = [:]
}

private struct CategoryGroupFrameKey: PreferenceKey {
    static let defaultValue: [Int64: CGRect] = [:]

    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct CategoryGroupSection: View {
    let group: CategoryGroup
    let imageSide: CGFloat
    let palette: CategoryPalette
    let imagePipeline: MallImagePipeline?
    let isActive: Bool
    let onOpenSubcategory: (Int64) -> Void

    @ScaledMetric(relativeTo: .body) private var titleSize = 14.0

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(), spacing: 0, alignment: .center),
            count: CategoryMetrics.gridColumnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CategoryMetrics.titleSpacing) {
                RoundedRectangle(cornerRadius: CategoryMetrics.titleLineCornerRadius)
                    .fill(palette.primary)
                    .frame(
                        width: CategoryMetrics.titleLineWidth,
                        height: CategoryMetrics.titleLineHeight)
                Text(group.root.name)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                    .accessibilityIdentifier("category.group.\(group.root.id).title")
                Spacer(minLength: 0)
            }
            if !group.children.isEmpty {
                // The reference still renders the group title when a root has
                // no children; only the grid is omitted.
                Color.clear.frame(height: CategoryMetrics.titleToGridSpacing)
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(group.children, id: \.id) { child in
                        CategorySubcategoryItem(
                            category: child,
                            imageSide: imageSide,
                            palette: palette,
                            imagePipeline: imagePipeline,
                            isActive: isActive,
                            onOpen: { onOpenSubcategory(child.id) }
                        )
                    }
                }
            }
        }
        .padding(.bottom, CategoryMetrics.groupBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CategorySubcategoryItem: View {
    let category: CategoryNode
    let imageSide: CGFloat
    let palette: CategoryPalette
    let imagePipeline: MallImagePipeline?
    let isActive: Bool
    let onOpen: () -> Void

    @ScaledMetric(relativeTo: .caption2) private var nameSize = 11.0

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: CategoryMetrics.subNameTopSpacing) {
                image
                Text(category.name)
                    .font(.system(size: nameSize))
                    .foregroundStyle(palette.onSurface)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CategoryMetrics.subItemPadding)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityIdentifier("category.sub.\(category.id)")
    }

    @ViewBuilder private var image: some View {
        if let imagePipeline {
            RemoteImage(
                url: category.imageURL,
                targetSize: CGSize(width: imageSide, height: imageSide),
                contentMode: .fill,
                pipeline: imagePipeline,
                isEnabled: isActive
            )
            .frame(width: imageSide, height: imageSide)
            .clipShape(RoundedRectangle(cornerRadius: CategoryMetrics.subImageCornerRadius))
            .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: CategoryMetrics.subImageCornerRadius)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
                .frame(width: imageSide, height: imageSide)
                .accessibilityHidden(true)
        }
    }
}
