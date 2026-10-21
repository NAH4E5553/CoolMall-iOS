import MallCore
import MallImages
import SwiftUI

/// Category tab entry (CATEGORY-01 / A-GOODS-01). The Scene owns visibility;
/// the App owns the injected read capability and image pipeline. The entry
/// creates one internal page model, drives the single read through
/// `.task(id:)` and tears it down when the page disappears. `onOpenSubcategory`
/// carries the real direct-child category id for the future LIST-01 route; no
/// navigation destination is provided by this view.
@MainActor
public struct CategoryEntryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: CategoryViewModel?

    private let categories: any CategoryLoading
    private let isActive: Bool
    private let imagePipeline: MallImagePipeline?
    private let showsReadVerification: Bool
    private let onOpenSubcategory: (Int64) -> Void

    public init(
        categories: any CategoryLoading,
        isActive: Bool,
        imagePipeline: MallImagePipeline? = nil,
        showsReadVerification: Bool = false,
        onOpenSubcategory: @escaping (Int64) -> Void
    ) {
        self.categories = categories
        self.isActive = isActive
        self.imagePipeline = imagePipeline
        self.showsReadVerification = showsReadVerification
        self.onOpenSubcategory = onOpenSubcategory
    }

    public var body: some View {
        Group {
            if let viewModel {
                CategoryPageView(
                    viewModel: viewModel,
                    isActive: isActive,
                    imagePipeline: imagePipeline,
                    showsReadVerification: showsReadVerification,
                    onOpenSubcategory: onOpenSubcategory
                )
            } else {
                // One frame before the drive task creates the model.
                CategoryLoadingView(palette: CategoryPalette.resolve(colorScheme))
            }
        }
        .task(id: DriveKey(active: isActive, ticket: viewModel?.readTicket ?? 0)) {
            if viewModel == nil {
                viewModel = CategoryViewModel(categories: categories)
            }
            guard let viewModel else { return }
            // Visibility loss cancels this task; the model's generation guard
            // rejects any late value/error from the cancelled service call.
            await viewModel.drive(active: isActive, ticket: viewModel.readTicket)
        }
        // The `.task` has usually returned after the first read; onDisappear is
        // the reliable view-removal hook that invalidates an in-flight retry.
        .onDisappear { viewModel?.pageTeardown() }
    }

    private struct DriveKey: Equatable {
        let active: Bool
        let ticket: UInt64
    }
}
