import Foundation
import NukeUI
import SwiftUI

/// Public, decorative HTTPS image. Sizes are points; missing/inactive images send no request.
@MainActor
public struct RemoteImage: View {
    private let url: URL?
    private let targetSize: CGSize
    private let contentMode: ContentMode
    private let pipeline: MallImagePipeline
    private let isEnabled: Bool
    @Environment(\.displayScale) private var displayScale

    public init(
        url: URL?, targetSize: CGSize, contentMode: ContentMode = .fill,
        pipeline: MallImagePipeline, isEnabled: Bool = true
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.pipeline = pipeline
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Group {
            if let request = pipeline.request(
                url: url, targetSize: targetSize, scale: displayScale,
                contentMode: contentMode, isEnabled: isEnabled)
            {
                LazyImage(request: request) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: contentMode)
                            .accessibilityIdentifier("home.image.success")
                    } else {
                        placeholder
                            .accessibilityLabel(state.error == nil ? "正在加载图片" : "图片加载失败")
                            .accessibilityIdentifier(
                                state.error == nil ? "home.image.placeholder" : "home.image.failure"
                            )
                            .overlay {
                                if state.isLoading {
                                    ProgressView().accessibilityIdentifier("home.image.loading")
                                }
                            }
                    }
                }
                .pipeline(pipeline.pipeline)
                // Identity belongs only to the leaf subscription. A superseded
                // SDK observer cannot deliver to the new URL/size/mode's view.
                .id(
                    ImageIdentity(
                        pipeline: ObjectIdentifier(pipeline), scale: displayScale, url: url,
                        width: ceil(targetSize.width * displayScale),
                        height: ceil(targetSize.height * displayScale), mode: contentMode == .fill))
            } else {
                placeholder.accessibilityLabel("暂无图片").accessibilityIdentifier("home.image.missing")
            }
        }
        .frame(width: validDimension(targetSize.width), height: validDimension(targetSize.height))
        .clipped()
    }

    private var placeholder: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                Image(systemName: "photo").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
    }

    private func validDimension(_ value: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : 0
    }
}

private struct ImageIdentity: Hashable {
    let pipeline: ObjectIdentifier
    let scale: CGFloat
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let mode: Bool
}
