import MallCore
import MallImages
import SwiftUI

@MainActor public struct FootprintEntryView: View {
    private let store: any FootprintBrowsing
    private let pipeline: MallImagePipeline?
    private let isActive: Bool
    private let onOpenProduct: (Int64) -> Void
    public init(
        store: any FootprintBrowsing, imagePipeline: MallImagePipeline?, isActive: Bool,
        onOpenProduct: @escaping (Int64) -> Void
    ) {
        self.store = store; pipeline = imagePipeline; self.isActive = isActive;
        self.onOpenProduct = onOpenProduct
    }
    public var body: some View {
        FootprintScreen(
            store: store, pipeline: pipeline, isActive: isActive, onOpenProduct: onOpenProduct
        ).id(store.scope)
    }
}
@MainActor private struct FootprintScreen: View {
    @State private var model: FootprintViewModel
    @State private var confirmClear = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let onOpenProduct: (Int64) -> Void
    init(
        store: any FootprintBrowsing, pipeline: MallImagePipeline?, isActive: Bool,
        onOpenProduct: @escaping (Int64) -> Void
    ) {
        _model = State(initialValue: FootprintViewModel(store: store)); self.pipeline = pipeline;
        self.isActive = isActive; self.onOpenProduct = onOpenProduct
    }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.red)
                    Button("重试") { model.retry() }.accessibilityIdentifier("footprints.retry")
                }.font(.subheadline).frame(maxWidth: .infinity).padding(12)
                    .background(.background)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if !model.loaded && model.operation == .initial { ProgressView("正在读取足迹") }
                        if model.loaded && model.items.isEmpty {
                            ContentUnavailableView(
                                "还没有浏览足迹", systemImage: "shoeprints.fill",
                                description: Text("浏览过的商品会显示在这里")
                            )
                            .accessibilityIdentifier("footprints.empty")
                        }
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), alignment: .top),
                                count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .center,
                            spacing: 12
                        ) {
                            ForEach(model.items) { item in card(item) }
                        }
                        if model.nextOffset != nil {
                            VStack(spacing: 8) {
                                if let error = model.appendError {
                                    Text(error).font(.footnote).foregroundStyle(.red)
                                }
                                if model.operation == .append { ProgressView("正在加载") }
                                Button(model.appendError == nil ? "加载更多" : "重试加载") {
                                    model.append()
                                }
                                .disabled(model.operation != nil).accessibilityIdentifier(
                                    "footprints.more")
                            }.padding().task { await model.loadMore(automatic: true) }
                        } else if model.loaded && !model.items.isEmpty {
                            Text("没有更多足迹了").font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("footprints.end")
                        }
                    }.padding(12).frame(maxWidth: 720).frame(maxWidth: .infinity).id(
                        "footprints.top")
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .background(.quinary).refreshable { await model.refresh() }
                .accessibilityIdentifier("footprints.page")
                .onChange(of: model.revision) { old, new in
                    if old != new { proxy.scrollTo("footprints.top", anchor: .top) }
                }
                .navigationTitle("我的足迹").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空 (\(model.total))", role: .destructive) { confirmClear = true }
                            .disabled(model.total == 0 || model.operation == .clear)
                            .accessibilityIdentifier("footprints.clear")
                    }
                }
                .confirmationDialog(
                    "清空全部足迹？", isPresented: $confirmClear, titleVisibility: .visible
                ) {
                    Button("清空足迹", role: .destructive) { model.clear() }.accessibilityIdentifier(
                        "footprints.confirmClear")
                } message: {
                    Text("仅清空当前身份的本机浏览记录，此操作无法撤销。")
                }
                .task(id: active) { if active { await model.observe() } else { model.stop() } }
                .onDisappear { model.stop() }
            }
        }
    }
    private func card(_ item: FootprintItem) -> some View {
        Button {
            onOpenProduct(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                FootprintThumbnail(item: item, pipeline: pipeline, isActive: active).aspectRatio(
                    1, contentMode: .fit
                ).padding(8)
                Text(item.title).font(.body).foregroundStyle(.primary).lineLimit(2)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        price(item); Spacer(minLength: 2); sold(item)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        price(item); sold(item)
                    }
                }
            }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("footprints.item.\(item.id)")
    }
    private func price(_ item: FootprintItem) -> some View {
        Text(item.priceYuan.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN"))))
            .font(.headline).foregroundStyle(.red)
    }
    private func sold(_ item: FootprintItem) -> some View {
        Text("已售\(item.sold)件").font(.caption).foregroundStyle(.secondary)
    }
}
