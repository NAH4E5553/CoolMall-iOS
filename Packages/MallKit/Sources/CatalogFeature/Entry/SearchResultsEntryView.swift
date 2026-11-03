import Foundation
import MallCore
import MallImages
import SwiftUI

@MainActor public struct SearchResultsEntryView: View {
    @State private var submission: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @State private var editingRevision: UInt64 = 0
    @State private var model: SearchResultsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private let history: any SearchHistoryRecording
    private let pipeline: MallImagePipeline?
    private let isActive: Bool
    private let onOpenProduct: (Int64) -> Void
    public init(
        keyword: String, loader: any ProductSearchLoading, categories: any CategoryLoading,
        history: any SearchHistoryRecording, historySaveFailed: Bool = false,
        featuredOnly: Bool = false, categoryIDs: [Int64] = [],
        imagePipeline: MallImagePipeline?, isActive: Bool, onOpenProduct: @escaping (Int64) -> Void
    ) {
        _model = State(
            initialValue: SearchResultsViewModel(
                keyword: keyword, loader: loader,
                categories: categories, history: history, historySaveFailed: historySaveFailed,
                featuredOnly: featuredOnly, categoryIDs: categoryIDs))
        self.history = history
        pipeline = imagePipeline; self.isActive = isActive; self.onOpenProduct = onOpenProduct
    }
    private var active: Bool { isActive && scenePhase == .active }
    public var body: some View {
        GeometryReader { geometry in
            content(width: geometry.size.width)
        }
    }
    @ViewBuilder private func content(width: CGFloat) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            controls.padding(12).background(.background)
            if model.state.failure != nil {
                HStack {
                    Text("商品读取失败，请重试").font(.subheadline)
                    Button("重试") { model.retry() }.accessibilityIdentifier("search.resultsRetry")
                }.padding(12)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !model.state.hasLoaded && model.state.operation != nil {
                        ProgressView("正在搜索")
                    }
                    if model.state.hasLoaded && model.state.items.isEmpty {
                        ContentUnavailableView(
                            "暂无匹配商品", systemImage: "magnifyingglass",
                            description: Text("试试其他关键词或筛选条件")
                        )
                        .accessibilityIdentifier("search.empty")
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.state.items) { item in card(item).id(item.id) }
                    }.scrollTargetLayout()
                    footer
                }.padding(12).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }.scrollBounceBehavior(.always, axes: .vertical)
                .scrollPosition(id: $model.scrollAnchor, anchor: .top)
                .refreshable { await model.refresh() }.accessibilityIdentifier("search.results")
                .id(model.resultsRevision)
        }.background(SearchStyle.background(scheme)).navigationTitle("")
            .navigationBarTitleDisplayMode(.inline).tint(SearchStyle.accent)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        SearchBarView(
                            text: $model.draft, busy: model.submitting || submission != nil,
                            focused: $searchFocused,
                            editingRevision: editingRevision
                        ) {
                            submitKeyword()
                        }.frame(maxWidth: .infinity)
                        Button {
                            model.toggleLayout()
                        } label: {
                            Image(
                                systemName: model.grid ? "list.bullet.rectangle" : "square.grid.2x2"
                            )
                            .font(.title3).frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(model.grid ? "切换单列" : "切换双列")
                            .accessibilityIdentifier("search.layout")
                    }
                    // One native toolbar host owns this row, including its layout action.
                    .frame(width: max(0, width - 44 - 16 - 8 - 8)).offset(x: 2.5)
                }
            }
            .accessibilityHidden(model.filterVisible)
            .overlay {
                if model.filterVisible {
                    SearchFilterView(model: model, pipeline: pipeline, active: active)
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = model.notice { SearchToastView(text: notice) }
            }
            .task(id: model.notice) {
                if model.notice != nil {
                    try? await Task.sleep(for: .seconds(3));
                    if !Task.isCancelled { model.dismissNotice() }
                }
            }
            .onChange(of: history.scope) { _, _ in
                submission?.cancel(); submission = nil; model.updateHistory(history)
            }
            .task(id: active) { await model.activate(active) }
            .onChange(of: active) { _, value in
                if !value { submission?.cancel(); submission = nil; model.stop() }
            }
            .onDisappear {
                submission?.cancel(); submission = nil; model.stop()
            }
    }
    private func submitKeyword() {
        guard submission == nil, !model.submitting,
            (!model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.query.featuredOnly || !model.query.categoryIDs.isEmpty)
        else { return }
        searchFocused = false
        editingRevision &+= 1
        submission = Task {
            await model.submitKeyword(); if !Task.isCancelled { submission = nil }
        }
    }
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), alignment: .top),
            count: model.grid && !typeSize.isAccessibilitySize ? 2 : 1)
    }
    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    model.showFilters()
                } label: {
                    Label("筛选", systemImage: "line.3.horizontal.decrease")
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.primary.opacity(0.035), in: Capsule())
                .accessibilityIdentifier("search.filter")
                sortButton(
                    "综合", field: "comprehensive", selected: model.query.sort == .comprehensive)
                sortButton(
                    "销量", field: "sales",
                    selected: [.salesAscending, .salesDescending].contains(model.query.sort))
                sortButton(
                    "价格", field: "price",
                    selected: [.priceAscending, .priceDescending].contains(model.query.sort))
            }.font(.subheadline).buttonStyle(.plain)
        }
    }
    private func sortButton(_ title: String, field: String, selected: Bool) -> some View {
        Button {
            model.sort(field)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if field != "comprehensive" {
                    Image(
                        systemName: selected
                            ? ([SearchSort.salesAscending, .priceAscending].contains(
                                model.query.sort) ? "arrow.up" : "arrow.down")
                            : "arrow.up.arrow.down"
                    )
                    .font(.caption2)
                }
            }.foregroundStyle(selected ? SearchStyle.accent : .primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(
                    selected ? SearchStyle.accent.opacity(0.1) : Color.primary.opacity(0.035),
                    in: Capsule())
        }.accessibilityIdentifier("search.sort.\(field)")
            .accessibilityValue(selected ? sortDescription : "未选择")
    }
    private var sortDescription: String {
        switch model.query.sort {
        case .comprehensive: "综合"
        case .salesAscending, .priceAscending: "从低到高"
        case .salesDescending, .priceDescending: "从高到低"
        }
    }
    @ViewBuilder private var footer: some View {
        if model.state.nextPage != nil {
            VStack(spacing: 8) {
                if model.state.appendFailure != nil { Text("加载失败，请重试").foregroundStyle(.secondary) }
                if model.state.operation == .append { ProgressView() }
                Button(model.state.appendFailure == nil ? "加载更多" : "重试加载") { model.more() }
                    .disabled(model.state.operation != nil).accessibilityIdentifier("search.more")
            }.padding().task { model.more(automatic: true) }.onDisappear { model.tailExited() }
        } else if model.state.hasLoaded && !model.state.items.isEmpty {
            Text("没有更多商品了").font(.footnote).foregroundStyle(.secondary).padding()
                .accessibilityIdentifier("search.end")
        }
    }
    private func card(_ item: SearchProductSummary) -> some View {
        Button {
            onOpenProduct(item.id)
        } label: {
            Group {
                if model.grid && !typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        picture(item).aspectRatio(1, contentMode: .fit)
                        description(item)
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        picture(item).frame(
                            width: typeSize.isAccessibilitySize ? 72 : 100,
                            height: typeSize.isAccessibilitySize ? 72 : 100)
                        description(item)
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("search.product.\(item.id)")
    }
    private func picture(_ item: SearchProductSummary) -> some View {
        GeometryReader { proxy in
            if let pipeline {
                RemoteImage(
                    url: item.imageURL, targetSize: proxy.size, contentMode: .fit,
                    pipeline: pipeline, isEnabled: active && !model.filterVisible)
            } else {
                Color.clear.overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
        }.accessibilityHidden(true)
    }
    private func description(_ item: SearchProductSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title).font(.body).foregroundStyle(.primary).lineLimit(2)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(
                    model.grid ? 2 : 1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(
                    item.priceYuan.formatted(
                        .currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
                )
                .font(.headline).foregroundStyle(.red)
                Spacer(minLength: 2)
                if let sold = item.sold {
                    Text("已售\(sold)件").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.top, 2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
