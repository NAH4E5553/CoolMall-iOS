import MallImages
import SwiftUI

/// Internal page composition: state projection + split layout. Reads the page
/// model directly (Observation tracks it); actions only call the model's
/// commands. No request state lives here.
struct CategoryPageView: View {
    let viewModel: CategoryViewModel
    let isActive: Bool
    let imagePipeline: MallImagePipeline?
    let showsReadVerification: Bool
    let onOpenSubcategory: (Int64) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = CategoryPalette.resolve(colorScheme)
        Group {
            switch viewModel.state {
            case .idle, .loading:
                CategoryLoadingView(palette: palette)
            case .ready(let snapshot):
                ready(snapshot, palette: palette)
            case .empty:
                CategoryEmptyView(palette: palette)
            case .failed:
                CategoryErrorView(palette: palette) { viewModel.requestRetry() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        // Reference CenterAlignedTopAppBar("分类", no back icon): the native
        // inline title keeps the centered title and the system bar material.
        .navigationTitle("分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.regularMaterial, for: .tabBar)
    }

    private func ready(_ snapshot: CategorySnapshot, palette: CategoryPalette) -> some View {
        VStack(spacing: 0) {
            if showsReadVerification {
                CategoryVerificationBar(
                    snapshot: snapshot, selectedRootID: viewModel.selectedRootID)
            }
            HStack(spacing: 0) {
                CategoryRootRailView(
                    snapshot: snapshot,
                    selectedRootID: viewModel.selectedRootID,
                    palette: palette,
                    onSelect: { viewModel.selectRoot($0) }
                )
                CategoryGroupListView(
                    snapshot: snapshot,
                    scrollRequest: viewModel.scrollRequest,
                    palette: palette,
                    imagePipeline: imagePipeline,
                    isActive: isActive,
                    onScrollSelection: { viewModel.selectFromScroll($0) },
                    onUserDrag: { viewModel.userInterruptedProgrammaticScroll() },
                    onOpenSubcategory: onOpenSubcategory
                )
            }
        }
    }
}
