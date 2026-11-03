import Foundation
import MallCore
import Observation

/// Page identity owns input and cancellable projections; the injected store alone owns committed history.
@MainActor @Observable final class SearchViewModel {
    var draft = ""
    private(set) var keywords: [String] = []
    private(set) var history: [String] = []
    private(set) var keywordLoading = false
    private(set) var keywordFailed = false
    private(set) var historyFailed = false
    private(set) var submitting = false
    private(set) var clearing = false
    private(set) var notice: String?
    private let loader: any SearchKeywordsLoading
    private var store: any SearchHistoryStoring
    private var active = false
    private var generation: UInt64 = 0
    @ObservationIgnored private var keywordTask: Task<Void, Never>?
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    init(loader: any SearchKeywordsLoading, history: any SearchHistoryStoring) {
        self.loader = loader; store = history
    }
    func updateHistory(_ store: any SearchHistoryStoring) {
        guard store.scope != self.store.scope else { return }
        generation &+= 1; keywordTask?.cancel(); historyTask?.cancel()
        self.store = store; history = []; historyFailed = false; notice = nil
        submitting = false; clearing = false; keywordLoading = false
        if active { reloadKeywords(); observeHistory() }
    }
    func activate(_ value: Bool) {
        guard value != active else { return }
        active = value; generation &+= 1
        if value {
            reloadKeywords(); observeHistory()
        } else {
            keywordTask?.cancel(); historyTask?.cancel(); keywordTask = nil; historyTask = nil
            keywordLoading = false; submitting = false; clearing = false
        }
    }
    func reloadKeywords() {
        guard active, !keywordLoading else { return }
        keywordLoading = true; keywordFailed = false
        let epoch = generation
        keywordTask = Task { [weak self, loader] in
            do {
                let values = try await loader.loadSearchKeywords()
                guard let self, self.active, self.generation == epoch, !Task.isCancelled else {
                    return
                }
                self.keywords = values; self.keywordLoading = false
            } catch {
                guard let self, self.active, self.generation == epoch else { return }
                self.keywordLoading = false
                self.keywordFailed = !(error is CancellationError) && !Task.isCancelled
            }
        }
    }
    func observeHistory() {
        guard active else { return }
        historyTask?.cancel(); historyFailed = false
        let epoch = generation
        historyTask = Task { [weak self, store] in
            do {
                let stream = try await store.changes()
                for await value in stream {
                    guard let self, self.active, self.generation == epoch, !Task.isCancelled else {
                        return
                    }
                    self.history = value.keywords; self.historyFailed = false
                }
            } catch {
                guard let self, self.active, self.generation == epoch, !Task.isCancelled else {
                    return
                }
                self.historyFailed = !(error is CancellationError)
            }
        }
    }
    /// Returns a navigation intent only while the same active page still owns this submission.
    func submit(_ text: String) async -> (keyword: String, historyFailed: Bool)? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, !word.isEmpty, !submitting, !clearing else { return nil }
        submitting = true; notice = nil; let epoch = generation
        var saveFailed = false
        do { try await store.record(word) } catch {
            if error is CancellationError || Task.isCancelled {
                if generation == epoch { submitting = false }; return nil
            }
            saveFailed = true
        }
        guard active, generation == epoch, !Task.isCancelled else {
            if generation == epoch { submitting = false }; return nil
        }
        // Remains single-flight until navigation deactivates the entry.
        return (word, saveFailed)
    }
    func clear() async {
        guard active, !clearing, !submitting else { return }
        clearing = true; notice = nil; let epoch = generation
        do { try await store.clear() } catch {
            guard active, generation == epoch else { return }
            if !(error is CancellationError), !Task.isCancelled { notice = "搜索历史清空失败，请重试" }
        }
        if active, generation == epoch { clearing = false }
    }
    func dismissNotice() { notice = nil }
    deinit { keywordTask?.cancel(); historyTask?.cancel() }
}
