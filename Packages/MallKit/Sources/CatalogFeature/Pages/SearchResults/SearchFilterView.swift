import MallCore
import MallImages
import SwiftUI

@MainActor struct SearchFilterView: View {
    @Bindable var model: SearchResultsViewModel
    let pipeline: MallImagePipeline?
    let active: Bool
    private enum PriceField: Hashable { case minimum, maximum }
    @FocusState private var focusedPrice: PriceField?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { close() }
                    .accessibilityLabel("关闭筛选").accessibilityAddTraits(.isButton)
                VStack(spacing: 0) {
                    HStack {
                        Text("筛选").font(.title3.bold()); Spacer()
                        Button {
                            close()
                        } label: {
                            Image(systemName: "xmark").padding(8)
                        }
                        .frame(minWidth: 44, minHeight: 44).foregroundStyle(.primary)
                        .accessibilityLabel("关闭筛选").accessibilityIdentifier("search.filterClose")
                    }.padding(16)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            priceRange
                            if model.categoryLoading { ProgressView("正在读取分类").padding() }
                            if model.categoryFailed {
                                Text("分类读取失败").foregroundStyle(.secondary)
                                Button("重试分类") { model.loadCategories() }.accessibilityIdentifier(
                                    "search.categoryRetry")
                            }
                            ForEach(model.roots, id: \.id) { root in group(root) }
                            if !model.categoryLoading && !model.categoryFailed
                                && model.roots.isEmpty
                            {
                                Text("暂无分类").foregroundStyle(.secondary)
                            }
                        }.padding(.horizontal, 12).padding(.bottom, 12)
                    }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier(
                        "search.filterContent")
                    if let error = model.filterError {
                        Text(error).font(.footnote).foregroundStyle(.red).padding(8)
                            .accessibilityIdentifier("search.filterError")
                    }
                    HStack(spacing: 12) {
                        Button("重置") {
                            focusedPrice = nil; model.resetFilters()
                        }.foregroundStyle(SearchStyle.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(Capsule().stroke(SearchStyle.accent, lineWidth: 1))
                            .accessibilityIdentifier("search.filterReset")
                        Button {
                            focusedPrice = nil; model.applyFilters()
                        } label: {
                            Text("确定").bold().foregroundStyle(.white).frame(
                                maxWidth: .infinity, minHeight: 44
                            )
                            .background(SearchStyle.accent.gradient, in: Capsule())
                        }.accessibilityIdentifier("search.filterApply")
                    }.buttonStyle(.plain).padding(12).background(.background)
                }.background(SearchStyle.background(scheme), in: RoundedRectangle(cornerRadius: 22))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .frame(
                        width: min(660, max(0, proxy.size.width - 32)),
                        height: min(680, max(0, proxy.size.height - 32))
                    )
                    .accessibilityAddTraits(.isModal)
                    .accessibilityElement(children: .contain)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.tint(SearchStyle.accent)
    }
    private var priceRange: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("价格区间").font(.headline)
            Text("高于最低价，不高于最高价").font(.caption).foregroundStyle(.secondary)
            HStack {
                priceField("最低价", text: $model.minimumDraft, field: .minimum, id: "search.minimum")
                Text("—").foregroundStyle(.tertiary)
                priceField("最高价", text: $model.maximumDraft, field: .maximum, id: "search.maximum")
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func close() { focusedPrice = nil; model.dismissFilters() }
    private func priceField(
        _ title: String, text: Binding<String>, field: PriceField, id: String
    ) -> some View {
        TextField(title, text: text).keyboardType(.decimalPad).font(.subheadline)
            .focused($focusedPrice, equals: field)
            .padding(12).overlay(Capsule().stroke(Color.secondary.opacity(0.15)))
            .accessibilityLabel(title).accessibilityIdentifier(id)
    }
    private func group(_ root: CategoryNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(root.name).font(.headline)
            ProductDetailCouponFlow(spacing: 8) {
                ForEach(model.children(root.id), id: \.id) { child in
                    Button {
                        model.toggleCategory(child.id)
                    } label: {
                        HStack(spacing: 6) {
                            if let pipeline {
                                RemoteImage(
                                    url: child.imageURL, targetSize: CGSize(width: 18, height: 18),
                                    contentMode: .fit, pipeline: pipeline, isEnabled: active
                                )
                                .frame(width: 18, height: 18).accessibilityHidden(true)
                            }
                            Text(child.name).font(.subheadline).multilineTextAlignment(.leading)
                        }.padding(.horizontal, 12).padding(.vertical, 10)
                            .foregroundStyle(
                                model.selectedCategories.contains(child.id)
                                    ? SearchStyle.accent : .primary
                            )
                            .background(
                                model.selectedCategories.contains(child.id)
                                    ? SearchStyle.accent.opacity(0.1) : .clear, in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    model.selectedCategories.contains(child.id)
                                        ? SearchStyle.accent : Color.secondary.opacity(0.15)))
                    }.buttonStyle(.plain).accessibilityIdentifier("search.category.\(child.id)")
                        .accessibilityAddTraits(
                            model.selectedCategories.contains(child.id) ? .isSelected : [])
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
