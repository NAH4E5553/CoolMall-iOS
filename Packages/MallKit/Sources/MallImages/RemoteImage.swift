import Foundation
import NukeUI
import SwiftUI

/// Public, decorative HTTPS image. Sizes are points. Inactive views pause requests while retaining
/// the same resource's loaded presentation; a changed resource/size/pipeline gets a new owner.
@MainActor
public struct RemoteImage: View {
    private let url: URL?
    private let targetSize: CGSize
    private let contentMode: ContentMode
    private let pipeline: MallImagePipeline
    private let isEnabled: Bool
    private let preservesIntrinsicAspectRatio: Bool
    @Environment(\.displayScale) private var displayScale

    public init(
        url: URL?, targetSize: CGSize, contentMode: ContentMode = .fill,
        pipeline: MallImagePipeline, isEnabled: Bool = true,
        preservesIntrinsicAspectRatio: Bool = false
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.pipeline = pipeline
        self.isEnabled = isEnabled
        self.preservesIntrinsicAspectRatio = preservesIntrinsicAspectRatio
    }

    public var body: some View {
        Group {
            if let request = pipeline.request(
                url: url, targetSize: targetSize, scale: displayScale,
                contentMode: preservesIntrinsicAspectRatio ? .fill : contentMode,
                // Request construction validates identity only; the leaf starts work when enabled.
                isEnabled: true)
            {
                ImagePresentation(configuration: self, request: request)
                    // Identity belongs only to the leaf subscription. A superseded
                    // SDK observer cannot deliver to the new URL/size/mode's view.
                    .id(
                        ImageIdentity(
                            pipeline: ObjectIdentifier(pipeline), scale: displayScale, url: url,
                            width: ceil(targetSize.width * displayScale),
                            height: ceil(targetSize.height * displayScale),
                            mode: contentMode == .fill,
                            natural: preservesIntrinsicAspectRatio))
            } else {
                placeholder.accessibilityLabel("暂无图片").accessibilityIdentifier("home.image.missing")
            }
        }
        .frame(
            width: validDimension(targetSize.width),
            height: preservesIntrinsicAspectRatio ? nil : validDimension(targetSize.height)
        )
        .clipped()
    }

    /// FetchImage.cancel() preserves the SDK's imageContainer. Keeping this leaf mounted also
    /// preserves that presentation through push/pop, even if the shared memory cache is evicted.
    private struct ImagePresentation: View {
        let configuration: RemoteImage
        let request: ImageRequest
        @StateObject private var loader = FetchImage()
        @State private var visible = false
        @State private var suspended = true

        var body: some View {
            Group {
                if let image = loader.image {
                    image.resizable().aspectRatio(contentMode: configuration.contentMode)
                        .accessibilityIdentifier("home.image.success")
                } else if !configuration.isEnabled {
                    configuration.placeholder.accessibilityLabel("暂无图片")
                        .accessibilityIdentifier("home.image.missing")
                } else {
                    configuration.placeholder
                        .accessibilityLabel(failed ? "图片加载失败" : "正在加载图片")
                        .accessibilityIdentifier(
                            failed ? "home.image.failure" : "home.image.placeholder"
                        )
                        .overlay {
                            if !suspended && loader.isLoading {
                                ProgressView().accessibilityIdentifier("home.image.loading")
                            }
                        }
                }
            }
            .onAppear {
                visible = true; reconcile()
            }
            .onChange(of: configuration.isEnabled) { _, _ in reconcile() }
            .onDisappear {
                visible = false; reconcile()
            }
        }
        private var failed: Bool {
            if case .failure? = loader.result { return true }
            return false
        }
        private func reconcile() {
            guard visible && configuration.isEnabled else {
                suspended = true; loader.cancel(); return
            }
            guard suspended else { return }
            suspended = false
            guard loader.image == nil else { return }
            loader.pipeline = configuration.pipeline.pipeline
            loader.load(request)
        }
    }

    private var placeholder: some View {
        Rectangle().fill(.quaternary)
            .overlay {
                Image(systemName: "photo").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(height: preservesIntrinsicAspectRatio ? validDimension(targetSize.width) : nil)
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
    let natural: Bool
}
