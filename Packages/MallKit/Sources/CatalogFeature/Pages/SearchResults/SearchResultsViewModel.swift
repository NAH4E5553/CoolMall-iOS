import Foundation
import MallCore
import Observation

@MainActor @Observable final class SearchResultsViewModel {
    var draft: String
    private(set) var query: SearchQuery
    private(set) var state: NumberedPageSnapshot<SearchProductSummary>
    private(set) var grid = true
    // A new query starts a new viewport; detail returns, refresh and layout keep this identity.
    private(set) var resultsRevision: UInt64 = 0
    var scrollAnchor: Int64?
    private(set) var filterVisible = false
    var selectedCategories: Set<Int64> = []
    var minimumDraft = ""
    var maximumDraft = ""
    private(set) var filterError: String?
    private(set) var categoryLoading = false
    private(set) var categoryFailed = false
    private(set) var categories: [CategoryNode] = []
    private(set) var notice: String?
    private(set) var submitting = false
    private let loader: any ProductSearchLoading
    private let categoryLoader: any CategoryLoading
    private var history: any SearchHistoryRecording
    private var pages: NumberedPageCoordinator<SearchProductSummary>
    private var active = false
    private var epoch: UInt64 = 0
    private var categoryEpoch: UInt64 = 0
    @ObservationIgnored private var categoryTask: Task<Void, Never>?
    private var categoriesLoaded = false
    init(
        keyword: String, loader: any ProductSearchLoading, categories: any CategoryLoading,
        history: any SearchHistoryRecording, historySaveFailed: Bool = false,
        featuredOnly: Bool = false
    ) {
        let query = SearchQuery(keyword: keyword, featuredOnly: featuredOnly)
        self.query = query; draft = query.keyword; self.loader = loader
        categoryLoader = categories; self.history = history
        let pages = Self.makePages(query, loader: loader)
        self.pages = pages; state = pages.snapshot
        notice = historySaveFailed ? "搜索历史未保存" : nil
        connect(pages)
    }
    private static func makePages(_ query: SearchQuery, loader: any ProductSearchLoading)
        -> NumberedPageCoordinator<SearchProductSummary>
    {
        NumberedPageCoordinator(pageSize: 10) { page, size in
            try await loader.search(query, page: page, pageSize: size)
        }
    }
    private func connect(_ owner: NumberedPageCoordinator<SearchProductSummary>) {
        let current = epoch
        owner.onChange = { [weak self] value in
            guard let self, self.epoch == current else { return }; self.state = value
        }
    }
    func activate(_ value: Bool) async {
        if value != active { epoch &+= 1; active = value; connect(pages) }
        pages.setActive(value)
        if value {
            await pages.loadInitial()
        } else {
            submitting = false; dismissFilters()
        }
    }
    func updateHistory(_ store: any SearchHistoryRecording) {
        guard store.scope != history.scope else { return }
        epoch &+= 1; history = store; submitting = false; notice = nil; connect(pages)
    }
    func stop() {
        active = false; epoch &+= 1; pages.setActive(false); state = pages.snapshot
        submitting = false; dismissFilters()
    }
    func refresh() async {
        guard active, !Task.isCancelled else { return }
        let owner = pages; let current = epoch
        // Native callback cancellation must not revoke an accepted page intent.
        // The existing owner still cancels on leaving or query replacement.
        let refresh = Task { @MainActor [weak self] in
            guard let self, self.active, self.epoch == current, self.pages === owner else { return }
            await owner.refresh()
        }
        await refresh.value
    }
    func retry() { pages.retry() }
    func more(automatic: Bool = false) { pages.loadMore(automatic: automatic) }
    func tailExited() { pages.tailExited() }
    func toggleLayout() { grid.toggle() }
    private func replace(_ value: SearchQuery) {
        guard active, value != query else { return }
        pages.setActive(false); pages.onChange = nil; epoch &+= 1; query = value
        pages = Self.makePages(value, loader: loader); state = pages.snapshot; scrollAnchor = nil
        resultsRevision &+= 1
        connect(pages); pages.setActive(true); pages.retry()
    }
    func submitKeyword() async {
        let word = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, (!word.isEmpty || query.featuredOnly), !submitting else { return }
        submitting = true; notice = nil; let current = epoch
        do { if !word.isEmpty { try await history.record(word) } } catch {
            guard active, epoch == current else { return }
            if error is CancellationError || Task.isCancelled { submitting = false; return }
            notice = "搜索历史未保存"
        }
        guard active, epoch == current, !Task.isCancelled else {
            if epoch == current { submitting = false }; return
        }
        submitting = false
        replace(
            SearchQuery(
                keyword: word, categoryIDs: query.categoryIDs,
                minimumPrice: query.minimumPrice, maximumPrice: query.maximumPrice,
                sort: query.sort, featuredOnly: query.featuredOnly
            ))
    }
    func sort(_ field: String) {
        guard active, !submitting else { return }
        let next: SearchSort
        switch field {
        case "sales":
            switch query.sort {
            case .salesAscending: next = .salesDescending
            case .salesDescending: next = .comprehensive
            default: next = .salesAscending
            }
        case "price":
            switch query.sort {
            case .priceAscending: next = .priceDescending
            case .priceDescending: next = .comprehensive
            default: next = .priceAscending
            }
        default: next = .comprehensive
        }
        replace(
            SearchQuery(
                keyword: query.keyword, categoryIDs: query.categoryIDs,
                minimumPrice: query.minimumPrice, maximumPrice: query.maximumPrice, sort: next,
                featuredOnly: query.featuredOnly))
    }
    func showFilters() {
        guard active, !submitting else { return }
        selectedCategories = Set(query.categoryIDs)
        minimumDraft = query.minimumPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        maximumDraft = query.maximumPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        filterError = nil; filterVisible = true
        if !categoriesLoaded { loadCategories() }
    }
    func dismissFilters() {
        filterVisible = false; categoryEpoch &+= 1; categoryTask?.cancel(); categoryTask = nil
        categoryLoading = false
    }
    func loadCategories() {
        guard active, filterVisible, !categoryLoading else { return }
        categoryLoading = true; categoryFailed = false; categoryEpoch &+= 1
        let current = categoryEpoch
        categoryTask = Task { [weak self, categoryLoader] in
            do {
                let values = try await categoryLoader.loadCategories()
                guard let self, self.active, self.filterVisible, self.categoryEpoch == current,
                    !Task.isCancelled
                else { return }
                self.categories = values; self.categoriesLoaded = true; self.categoryLoading = false
            } catch {
                guard let self, self.active, self.categoryEpoch == current else { return }
                self.categoryLoading = false
                self.categoryFailed = !(error is CancellationError) && !Task.isCancelled
            }
        }
    }
    var roots: [CategoryNode] { ordered(categories.filter { $0.parentID == nil }) }
    func children(_ id: Int64) -> [CategoryNode] {
        ordered(categories.filter { $0.parentID == id })
    }
    private func ordered(_ values: [CategoryNode]) -> [CategoryNode] {
        values.sorted { $0.sortNum == $1.sortNum ? $0.id < $1.id : $0.sortNum < $1.sortNum }
    }
    func toggleCategory(_ id: Int64) {
        if selectedCategories.contains(id) {
            selectedCategories.remove(id)
        } else {
            selectedCategories.insert(id)
        }
    }
    func resetFilters() {
        selectedCategories = []; minimumDraft = ""; maximumDraft = ""; filterError = nil
    }
    private func amount(_ text: String) throws -> Decimal? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            parts.count == 1 || parts[1].count <= 2,
            let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
            !amount.isNaN, amount >= 0
        else { throw PageReadFailure.invalidConfiguration }
        let integer = parts[0].drop(while: { $0 == "0" })
        let whole = integer.isEmpty ? "0" : String(integer)
        let fraction =
            parts.count == 2
            ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
        let normalized = whole + (fraction.isEmpty ? "" : "." + fraction)
        guard NSDecimalNumber(decimal: amount).stringValue == normalized else {
            throw PageReadFailure.invalidConfiguration
        }
        return amount
    }
    func applyFilters() {
        guard active, filterVisible, !submitting else { return }
        do {
            let minimum = try amount(minimumDraft); let maximum = try amount(maximumDraft)
            if let minimum, let maximum, minimum > maximum {
                filterError = "最低价不能高于最高价"; return
            }
            let next = SearchQuery(
                keyword: query.keyword, categoryIDs: Array(selectedCategories),
                minimumPrice: minimum, maximumPrice: maximum, sort: query.sort,
                featuredOnly: query.featuredOnly)
            guard next.isValid else { filterError = "筛选条件无效"; return }
            dismissFilters(); replace(next)
        } catch { filterError = "请填写有效的非负价格，最多两位小数" }
    }
    func dismissNotice() { notice = nil }
    deinit { categoryTask?.cancel() }
}
