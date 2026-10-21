import SwiftUI

/// Left rail: 100pt wide, surface background, 50pt rows. The selected row is
/// surface and the unselected areas are two CONTINUOUS background blocks (above
/// and below the selected row) drawn against the viewport, matching the
/// reference Canvas:
///
/// - upper block: viewport top → selected row top; trailing bottom corner 16pt
///   (top corner 16pt only while the first row touches the viewport top);
/// - lower block: selected row bottom → viewport bottom; trailing top corner
///   16pt and, per the confirmed iOS requirement (2026-10-22), trailing bottom
///   corner 16pt as the whole block's outer contour;
/// - when the selected row is scrolled out of the viewport, one full-viewport
///   unselected block is drawn (no fictional row).
///
/// The blocks are viewport-fixed geometry, measured from the real row frames;
/// they are NOT inside the row selection animation, so their corner radii snap
/// to the target shape instead of interpolating from 0 (R-CATEGORY-01-05).
/// Only the text color/size and the 3x24 indicator keep the reference
/// animations.
struct CategoryRootRailView: View {
    let snapshot: CategorySnapshot
    let selectedRootID: Int64?
    let palette: CategoryPalette
    let onSelect: (Int64) -> Void

    @State private var rowFrames: [Int64: CGRect] = [:]

    private static let spaceName = "category.left.viewport"

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                palette.surface
                backgroundBlocks(viewport: geometry.size)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(snapshot.groups.enumerated()), id: \.element.id) {
                                _, group in
                                CategoryRootRow(
                                    id: group.root.id,
                                    name: group.root.name,
                                    isSelected: group.root.id == selectedRootID,
                                    palette: palette,
                                    onSelect: { onSelect(group.root.id) }
                                )
                                .id(group.root.id)
                                .background(frameReader(for: group.root.id))
                            }
                            // Reference bottom placeholder; transparent so the
                            // lower viewport block stays visible behind it.
                            Color.clear.frame(height: CategoryMetrics.rootRowMinHeight)
                        }
                    }
                    .onChange(of: selectedRootID) { _, rootID in
                        guard let rootID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(rootID, anchor: .top)
                        }
                    }
                }
            }
            .coordinateSpace(name: Self.spaceName)
            .onPreferenceChange(CategoryRootFrameKey.self) { frames in
                rowFrames = frames
            }
        }
        .frame(width: CategoryMetrics.leftColumnWidth)
    }

    @ViewBuilder
    private func backgroundBlocks(viewport: CGSize) -> some View {
        let width = viewport.width
        let height = viewport.height
        Group {
            if let frame = selectedRootID.flatMap({ rowFrames[$0] }) {
                if frame.maxY <= 0 {
                    // Selected row is above the viewport: the whole viewport is one
                    // lower-style unselected block.
                    block(width: width, height: height, topTrailing: 0, bottomTrailing: 16)
                } else if frame.minY >= height {
                    // Selected row is below the viewport: the whole viewport is one
                    // upper-style unselected block.
                    block(
                        width: width, height: height,
                        topTrailing: upperTopTrailing, bottomTrailing: 16)
                } else {
                    let upperHeight = max(0, min(frame.minY, height))
                    if upperHeight > 0 {
                        block(
                            width: width, height: upperHeight,
                            topTrailing: upperTopTrailing, bottomTrailing: 16)
                    }
                    let lowerY = max(0, frame.maxY)
                    let lowerHeight = max(0, height - lowerY)
                    if lowerHeight > 0 {
                        block(
                            width: width, height: lowerHeight,
                            topTrailing: 16, bottomTrailing: 16
                        )
                        .offset(y: lowerY)
                    }
                }
            }
        }
        // Background geometry and corner radii must snap; only the text and
        // indicator keep their animations (R-CATEGORY-01-05).
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func block(
        width: CGFloat, height: CGFloat, topTrailing: CGFloat, bottomTrailing: CGFloat
    ) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: bottomTrailing,
            topTrailingRadius: topTrailing
        )
        .fill(palette.background)
        .frame(width: width, height: height)
    }

    /// The reference rounds the upper block's top corner only while the first
    /// row still touches the viewport top (firstVisibleItemIndex == 0).
    private var upperTopTrailing: CGFloat {
        guard let firstRoot = snapshot.groups.first?.root.id,
            let firstFrame = rowFrames[firstRoot], firstFrame.minY >= -0.5
        else { return 0 }
        return CategoryMetrics.groupCornerRadius
    }

    private func frameReader(for id: Int64) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CategoryRootFrameKey.self,
                value: [id: proxy.frame(in: .named(Self.spaceName))]
            )
        }
    }
}

private struct CategoryRootRow: View {
    let id: Int64
    let name: String
    let isSelected: Bool
    let palette: CategoryPalette
    let onSelect: () -> Void

    @ScaledMetric(relativeTo: .caption) private var baseFontSize = 12.0

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
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("category.root.\(id)")
    }
}

private struct CategoryRootFrameKey: PreferenceKey {
    static let defaultValue: [Int64: CGRect] = [:]

    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
