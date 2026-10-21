import SwiftUI

/// Left rail: 100pt wide, surface background, 50pt rows. The selected row is
/// surface and the unselected areas are the page background, so the white
/// selected row visually joins the right pane; a 3x24 primary indicator sits at
/// the leading edge and the selected label is 1.2x/heavy in primary. The
/// reference draws the background regions behind the list with 16pt right
/// corners; fixed-height rows reproduce the same boundary with per-row trailing
/// corner radii (the selected-1 row gets a bottom-trailing corner, the
/// selected+1 row a top-trailing one, the first row a top-trailing corner).
struct CategoryRootRailView: View {
    let snapshot: CategorySnapshot
    let selectedRootID: Int64?
    let palette: CategoryPalette
    let onSelect: (Int64) -> Void

    private var selectedIndex: Int? {
        guard let selectedRootID else { return nil }
        return snapshot.index(ofRoot: selectedRootID)
    }

    var body: some View {
        GeometryReader { geometry in
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
                        // Reference bottom placeholder plus the reference canvas'
                        // grey region below the rows; the rail itself stays
                        // surface so the rounded boundary reveals white.
                        Spacer(minLength: CategoryMetrics.rootRowMinHeight)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: fillerTopTrailingRadius
                                )
                                .fill(palette.background)
                            )
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .onChange(of: selectedRootID) { _, rootID in
                    guard let rootID else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(rootID, anchor: .top)
                    }
                }
            }
        }
        .frame(width: CategoryMetrics.leftColumnWidth)
        .background(palette.surface)
    }

    /// Below the rows the reference draws the page background to the viewport
    /// bottom; when the last row is the selected one that region starts with the
    /// same 16pt top-trailing corner used for the selected+1 boundary.
    private var fillerTopTrailingRadius: CGFloat {
        guard let selectedIndex, selectedIndex == snapshot.groups.count - 1 else { return 0 }
        return CategoryMetrics.groupCornerRadius
    }

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
            .animation(.easeInOut(duration: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("category.root.\(id)")
    }
}
