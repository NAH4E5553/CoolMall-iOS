#if DEBUG
    import Foundation
    import MallCore

    /// Explicit controlled read services; Release always assembles HTTPProductSearchService.
    actor SearchUITestSupport: ProductSearchLoading, SearchKeywordsLoading, CategoryLoading {
        let mode: String
        private var reads = 0
        private var keywordReads = 0
        private var categoryReads = 0
        private var lastQuery: SearchQuery?
        private var pageReads: [Int: Int] = [:]
        private let supported: Set<String> = [
            "valid", "entry-categories", "empty", "retry", "hot-error", "hot-empty", "hot-retry",
            "category-retry", "long", "refresh-retry", "append-retry",
            "history-read-retry", "history-write-retry", "history-clear-retry",
        ]
        init(mode: String) { self.mode = mode }
        static func make(arguments: [String]) -> SearchUITestSupport? {
            guard let index = arguments.firstIndex(of: "--ui-search-fixture") else { return nil }
            let mode = arguments.indices.contains(index + 1) ? arguments[index + 1] : "invalid"
            return SearchUITestSupport(mode: mode)
        }
        func loadSearchKeywords() throws -> [String] {
            guard supported.contains(mode) else {
                throw PageReadFailure.invalidConfiguration
            }
            keywordReads += 1
            if mode == "hot-error" || (mode == "hot-retry" && keywordReads == 1) {
                throw PageReadFailure.timeout
            }
            if mode == "hot-empty" { return [] }
            return ["Xiaomi 17", "Xiaomi 17 Pro", "智能摄像机", "路由器 BE7000", "小爱音箱"]
        }
        func loadCategories() throws -> [CategoryNode] {
            categoryReads += 1
            if mode == "category-retry" && categoryReads == 1 { throw PageReadFailure.timeout }
            let first: [CategoryNode] = [
                .init(id: 1, name: "手机", parentID: nil, sortNum: 0, imageURL: nil),
                .init(id: 2, name: "Xiaomi 数字旗舰", parentID: 1, sortNum: 0, imageURL: nil),
                .init(id: 3, name: "Xiaomi MIX 系列", parentID: 1, sortNum: 1, imageURL: nil),
                .init(id: 4, name: "智能家居", parentID: nil, sortNum: 1, imageURL: nil),
                .init(id: 5, name: "智能安防", parentID: 4, sortNum: 0, imageURL: nil),
            ]
            let more: [CategoryNode] = (10...19).flatMap { index in
                [
                    CategoryNode(
                        id: Int64(index * 10), name: "分类分组\(index)", parentID: nil, sortNum: index,
                        imageURL: nil),
                    CategoryNode(
                        id: Int64(index * 10 + 1), name: "子分类\(index)", parentID: Int64(index * 10),
                        sortNum: 0, imageURL: nil),
                ]
            }
            return first + more
        }
        func search(_ query: SearchQuery, page: Int, pageSize: Int) throws -> NumberedPage<
            SearchProductSummary
        > {
            reads += 1
            if mode == "retry" && reads == 1 { throw PageReadFailure.timeout }
            guard supported.contains(mode) else {
                throw PageReadFailure.invalidConfiguration
            }
            if query != lastQuery { lastQuery = query; pageReads = [:] }
            pageReads[page, default: 0] += 1
            if mode == "refresh-retry" && page == 1 && pageReads[page] == 2 {
                throw PageReadFailure.timeout
            }
            if mode == "append-retry" && page == 2 && pageReads[page] == 1 {
                throw PageReadFailure.timeout
            }
            let count =
                mode == "long"
                ? 60 : (mode == "entry-categories" ? 33 : (mode == "append-retry" ? 23 : 13))
            let suffix = mode == "refresh-retry" && (pageReads[1] ?? 0) >= 3 ? " · 已刷新" : ""
            var items: [SearchProductSummary] = (1...count).map { index in
                let productID = Int64(830000 + index)
                let price = Decimal(index * 100)
                let sold = Int64(count + 1 - index)
                return SearchProductSummary(
                    id: productID, title: "Xiaomi 17 \(index)" + suffix,
                    subtitle: "徕卡光学 · 旗舰性能", imageURL: nil,
                    priceYuan: price, sold: sold)
            }
            if mode == "entry-categories", !query.categoryIDs.isEmpty {
                // Distinct products prove real direct-child IDs reach the result query.
                let productIDs = Set(query.categoryIDs.map { $0 + 29000 })
                items = items.filter { productIDs.contains($0.id) }
            }
            if query.featuredOnly { items = items.filter { $0.id <= 830011 } }
            if mode == "empty" || query.keyword == "无结果" { items = [] }
            if let min = query.minimumPrice { items = items.filter { $0.priceYuan > min } }
            if let max = query.maximumPrice { items = items.filter { $0.priceYuan <= max } }
            switch query.sort {
            case .comprehensive: break
            case .priceAscending: items.sort { $0.priceYuan < $1.priceYuan }
            case .priceDescending: items.sort { $0.priceYuan > $1.priceYuan }
            case .salesAscending: items.sort { ($0.sold ?? 0) < ($1.sold ?? 0) }
            case .salesDescending: items.sort { ($0.sold ?? 0) > ($1.sold ?? 0) }
            }
            let start = min(items.count, (page - 1) * pageSize)
            return NumberedPage(
                items: Array(items.dropFirst(start).prefix(pageSize)), page: page, size: pageSize,
                total: Int64(items.count))
        }
    }

    /// DEBUG-only protocol fault injection. The persistent owner remains the sole history source.
    /// A simulated boundary failure proves UI recovery, not an actual disk commit failure.
    actor SearchHistoryUITestSupport: SearchHistoryStoring {
        nonisolated let scope: SearchHistoryScope
        private let owner: any SearchHistoryStoring
        private let mode: String
        private var seedPending: Bool
        private var reads = 0
        private var writes = 0
        private var clears = 0
        private init(owner: any SearchHistoryStoring, mode: String, seed: Bool) {
            self.owner = owner; self.mode = mode; scope = owner.scope; seedPending = seed
        }
        static func make(
            owner: any SearchHistoryStoring, arguments: [String]
        ) -> (any SearchHistoryStoring)? {
            guard let index = arguments.firstIndex(of: "--ui-search-fixture"),
                arguments.indices.contains(index + 1)
            else { return nil }
            let mode = arguments[index + 1]
            guard
                ["history-read-retry", "history-write-retry", "history-clear-retry"].contains(mode)
            else { return nil }
            return SearchHistoryUITestSupport(
                owner: owner, mode: mode, seed: arguments.contains("--ui-search-history-seed"))
        }
        func changes() async throws -> AsyncStream<SearchHistorySnapshot> {
            reads += 1
            if seedPending { seedPending = false; try await owner.record("已有历史") }
            if mode == "history-read-retry" && reads == 1 { throw SearchHistoryFailure.readFailed }
            return try await owner.changes()
        }
        func record(_ keyword: String) async throws {
            writes += 1
            if mode == "history-write-retry" && writes == 1 {
                throw SearchHistoryFailure.writeFailed
            }
            try await owner.record(keyword)
        }
        func clear() async throws {
            clears += 1
            if mode == "history-clear-retry" && clears == 1 {
                throw SearchHistoryFailure.writeFailed
            }
            try await owner.clear()
        }
    }
#endif
