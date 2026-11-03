import MallCore
import MallImages
import SwiftUI

@MainActor struct FootprintPreviewView: View {
    @State private var model: FootprintPreviewViewModel
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let onShowAll: () -> Void
    let onOpenProduct: (Int64) -> Void
    init(
        store: any FootprintBrowsing, pipeline: MallImagePipeline?, isActive: Bool,
        onShowAll: @escaping () -> Void, onOpenProduct: @escaping (Int64) -> Void
    ) {
        _model = State(initialValue: FootprintPreviewViewModel(store: store));
        self.pipeline = pipeline; self.isActive = isActive; self.onShowAll = onShowAll;
        self.onOpenProduct = onOpenProduct
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text("我的足迹").foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "shoeprints.fill").foregroundStyle(.orange)
                }.font(.headline)
                Spacer()
                Button(action: onShowAll) {
                    HStack(spacing: 4) {
                        Text("查看全部"); Image(systemName: "chevron.right")
                    }.font(.subheadline)
                }
                .accessibilityIdentifier("me.footprints.all")
            }
            if let error = model.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if !model.loaded && model.error == nil {
                ProgressView("正在读取足迹")
            } else if model.items.isEmpty {
                Text("还没有浏览记录，去看看喜欢的商品吧").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("me.footprints.empty")
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(model.items) { item in
                            Button {
                                onOpenProduct(item.id)
                            } label: {
                                FootprintThumbnail(
                                    item: item, pipeline: pipeline, isActive: isActive
                                ).frame(width: 88, height: 88)
                                    .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel(item.title)
                                .accessibilityIdentifier("me.footprint.\(item.id)")
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
            .task(id: isActive) { if isActive { await model.observe() } else { model.stop() } }
            .onDisappear { model.stop() }
    }
}
@MainActor struct FootprintThumbnail: View {
    let item: FootprintItem
    let pipeline: MallImagePipeline?
    let isActive: Bool
    var body: some View {
        GeometryReader { proxy in
            if let pipeline {
                RemoteImage(
                    url: item.imageURL, targetSize: proxy.size, contentMode: .fit,
                    pipeline: pipeline, isEnabled: isActive)
            } else {
                Color.clear.overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
        }.accessibilityHidden(true)
    }
}
