import Foundation
import MallCore
import SwiftUI

@MainActor public struct SearchEntryView: View {
    @FocusState private var searchFocused: Bool
    @State private var editingRevision: UInt64 = 0
    @State private var model: SearchViewModel
    @State private var command: Task<Void, Never>?
    @State private var confirmingClear = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    private let history: any SearchHistoryStoring
    private let isActive: Bool
    private let onSearch: (String, Bool) -> Void
    public init(
        loader: any SearchKeywordsLoading, history: any SearchHistoryStoring,
        isActive: Bool, onSearch: @escaping (String, Bool) -> Void
    ) {
        _model = State(initialValue: SearchViewModel(loader: loader, history: history))
        self.history = history; self.isActive = isActive; self.onSearch = onSearch
    }
    private var active: Bool { isActive && scenePhase == .active }
    public var body: some View {
        GeometryReader { geometry in
            content(width: geometry.size.width)
        }
    }
    @ViewBuilder private func content(width: CGFloat) -> some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.historyFailed {
                    VStack(alignment: .leading) {
                        Text("搜索历史读取失败").foregroundStyle(.secondary)
                        Button("重试历史") { model.observeHistory() }.accessibilityIdentifier(
                            "search.historyRetry")
                    }
                }
                if !model.history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("搜索历史").font(.headline)
                            Spacer()
                            Button {
                                confirmingClear = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .frame(minWidth: 44, minHeight: 44).accessibilityLabel("清空搜索历史")
                            .accessibilityIdentifier("search.clear")
                            .disabled(model.clearing || model.submitting)
                        }
                        tags(model.history, prefix: "search.history")
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("推荐搜索").font(.headline)
                    if model.keywordLoading { ProgressView("正在读取推荐搜索") }
                    if model.keywordFailed {
                        Text("推荐搜索读取失败").font(.subheadline).foregroundStyle(.secondary)
                        Button("重试推荐") { model.reloadKeywords() }.accessibilityIdentifier(
                            "search.keywordsRetry")
                    } else if !model.keywordLoading && model.keywords.isEmpty {
                        Text("暂无推荐搜索").foregroundStyle(.secondary)
                    }
                    tags(model.keywords, prefix: "search.keyword")
                }
            }.padding(16).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
            .background(SearchStyle.background(scheme)).navigationTitle("")
            .navigationBarTitleDisplayMode(.inline).tint(SearchStyle.accent)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SearchBarView(
                        text: $model.draft, busy: model.submitting || command != nil,
                        focused: $searchFocused,
                        editingRevision: editingRevision
                    ) {
                        submit(model.draft)
                    }
                    // Reserve the native Back control (44pt), its leading inset (16pt),
                    // and an 8pt gap on each side of the remaining search field.
                    .frame(width: max(0, width - 44 - 16 - 8 - 8))
                    // Balance the visible gaps around the native principal toolbar slot.
                    .offset(x: 2.5)
                }
            }
            .alert("清空搜索历史？", isPresented: $confirmingClear) {
                Button("清空", role: .destructive) {
                    guard command == nil else { return }
                    command = Task {
                        await model.clear(); if !Task.isCancelled { command = nil }
                    }
                }
                .accessibilityIdentifier("search.confirmClear")
                Button("取消", role: .cancel) {}.accessibilityIdentifier("search.cancelClear")
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
                command?.cancel(); command = nil; confirmingClear = false;
                model.updateHistory(history)
            }
            .task(id: active) { model.activate(active) }
            .onChange(of: active) { _, value in
                model.activate(value);
                if !value { command?.cancel(); command = nil; confirmingClear = false }
            }
            .onDisappear {
                command?.cancel(); command = nil; model.activate(false)
            }
    }
    private func submit(_ text: String) {
        guard command == nil, !model.submitting, !model.clearing,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        searchFocused = false
        editingRevision &+= 1
        command = Task {
            if let result = await model.submit(text) {
                onSearch(result.keyword, result.historyFailed)
            }
            if !Task.isCancelled { command = nil }
        }
    }
    private func tags(_ words: [String], prefix: String) -> some View {
        ProductDetailCouponFlow(spacing: 8) {
            ForEach(words, id: \.self) { word in
                Button {
                    submit(word)
                } label: {
                    Text(word).font(.body).foregroundStyle(.primary).multilineTextAlignment(
                        .leading
                    )
                    .padding(.horizontal, 16).padding(.vertical, 10).background(
                        .background, in: Capsule())
                }.buttonStyle(.plain).disabled(model.submitting || model.clearing)
                    .accessibilityIdentifier("\(prefix).\(word)")
            }
        }
    }
}
