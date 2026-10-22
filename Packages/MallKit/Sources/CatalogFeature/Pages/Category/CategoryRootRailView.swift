import SwiftUI

/// Left rail: default 100pt (132pt at accessibility Dynamic Type), surface
/// background, 50pt rows. The selected row is surface; the unselected rows form
/// ONE continuous background block per side, but only across the ACTUAL rows —
/// never to the viewport top or bottom (user clarification 2026-10-22):
///
/// - selecting the first row: no upper block; the lower block runs from the
///   second row to the last row, with trailing top/bottom corners;
/// - selecting a middle row: upper block from the first row to selected-1
///   (top+bottom trailing corners), lower block from selected+1 to the last row
///   (top+bottom trailing corners);
/// - selecting the last row: no lower block; the upper block ends at the row
///   before the selected row.
///
/// The empty viewport above/below the row range is the rail's surface (white),
/// not a background mask. Rows are contiguous, so the block has no per-row
/// notches; only the first/last rows of each block carry the 16pt trailing
/// corner. The background shape has no animation (R-CATEGORY-01-05); the text
/// color/size and the 3x24 indicator keep the reference animations.
struct CategoryRootRailView: View {
    let snapshot: CategorySnapshot
    let selectedRootID: Int64?
    let palette: CategoryPalette
    let onSelect: (Int64) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var railWidth: CGFloat {
        typeSize.isAccessibilitySize
            ? CategoryMetrics.accessibleLeftColumnWidth : CategoryMetrics.leftColumnWidth
    }

    private var selectedIndex: Int? {
        guard let selectedRootID else { return nil }
        return snapshot.index(ofRoot: selectedRootID)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.groups.enumerated()), id: \.element.id) {
                        index, group in
                        CategoryRootRow(
                            id: group.root.id,
                            name: group.root.name,
                            isSelected: group.root.id == selectedRootID,
                            hasSelection: selectedIndex != nil,
                            palette: palette,
                            topTrailingRadius: topTrailingRadius(at: index),
                            bottomTrailingRadius: bottomTrailingRadius(at: index),
                            onSelect: { onSelect(group.root.id) }
                        )
                        .id(group.root.id)
                    }
                    // Reference list bottom padding; transparent so the rail
                    // surface (not an unselected mask) remains below the rows.
                    Color.clear.frame(height: CategoryMetrics.rootRowMinHeight)
                }
            }
            .accessibilityIdentifier("category.left.scroll")
            .onChange(of: selectedRootID) { _, rootID in
                guard let rootID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(rootID, anchor: .top)
                }
            }
        }
        .frame(width: railWidth)
        .background(palette.surface)
    }

    /// Upper block: rows 0..<selected; lower block: rows selected+1..<count.
    /// Only the first row of each block gets the top-trailing corner and only
    /// the last row gets the bottom-trailing corner.
    private func topTrailingRadius(at index: Int) -> CGFloat {
        guard let selectedIndex else { return 0 }
        if index < selectedIndex { return index == 0 ? CategoryMetrics.groupCornerRadius : 0 }
        if index > selectedIndex {
            return index == selectedIndex + 1 ? CategoryMetrics.groupCornerRadius : 0
        }
        return 0
    }

    private func bottomTrailingRadius(at index: Int) -> CGFloat {
        guard let selectedIndex else { return 0 }
        if index < selectedIndex {
            return index == selectedIndex - 1 ? CategoryMetrics.groupCornerRadius : 0
        }
        if index > selectedIndex {
            return index == snapshot.groups.count - 1 ? CategoryMetrics.groupCornerRadius : 0
        }
        return 0
    }
}

private struct CategoryRootRow: View {
    let id: Int64
    let name: String
    let isSelected: Bool
    let hasSelection: Bool
    let palette: CategoryPalette
    let topTrailingRadius: CGFloat
    let bottomTrailingRadius: CGFloat
    let onSelect: () -> Void

    @ScaledMetric(relativeTo: .caption) private var baseFontSize = 12.0

    private var fill: Color {
        (!hasSelection || isSelected) ? palette.surface : palette.background
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(palette.primary)
                        .frame(
                            width: isSelected ? CategoryMetrics.indicatorWidth : 0,
                            height: CategoryMetrics.indicatorHeight
                        )
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
                    Spacer(minLength: 0)
                }
                Text(name)
                    .font(
                        .system(
                            size: isSelected ? baseFontSize * 1.2 : baseFontSize,
                            weight: isSelected ? .heavy : .regular
                        )
                    )
                    .foregroundStyle(isSelected ? palette.primary : palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .animation(.easeInOut(duration: 0.3), value: isSelected)
            }
            .frame(maxWidth: .infinity, minHeight: CategoryMetrics.rootRowMinHeight)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: bottomTrailingRadius,
                    topTrailingRadius: topTrailingRadius
                )
                .fill(fill)
            )
            // The block geometry/corners must snap; the row's text and
            // indicator animations are declared on those leaves above.
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("category.root.\(id)")
    }
}
