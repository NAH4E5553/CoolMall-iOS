#if DEBUG
    import Foundation
    import MallCore
    import SwiftUI

    #Preview("搜索历史与推荐") {
        NavigationStack {
            SearchEntryView(
                loader: SearchPreviewValues(), history: SearchPreviewValues(),
                isActive: true, onSearch: { _, _ in })
        }
    }
    #Preview("双列搜索结果") {
        NavigationStack {
            SearchResultsEntryView(
                keyword: "Xiaomi 17", loader: SearchPreviewValues(),
                categories: SearchPreviewValues(), history: SearchPreviewValues(),
                imagePipeline: nil,
                isActive: true, onOpenProduct: { _ in })
        }
    }
    #Preview("深色推荐读取失败") {
        NavigationStack {
            SearchEntryView(
                loader: SearchPreviewValues(failed: true), history: SearchPreviewValues(),
                isActive: true, onSearch: { _, _ in })
        }.preferredColorScheme(.dark)
    }
    /// Static preview snapshots only; never assembled by the App or used as persistence fallback.
    private struct SearchPreviewValues: SearchKeywordsLoading, ProductSearchLoading,
        CategoryLoading,
        SearchHistoryStoring
    {
        var failed = false
        let scope = SearchHistoryScope(environment: "preview", accountID: nil)
        func loadSearchKeywords() throws -> [String] {
            if failed { throw PageReadFailure.timeout }
            return ["Xiaomi 17", "Xiaomi 17 Pro", "Xiaomi 17 Ultra", "智能摄像机", "路由器 BE7000"]
        }
        func changes() -> AsyncStream<SearchHistorySnapshot> {
            AsyncStream {
                $0.yield(.init(keywords: ["智能摄像机", "小爱音箱"], revision: 1)); $0.finish()
            }
        }
        func record(_ keyword: String) {}
        func clear() {}
        func loadCategories() -> [CategoryNode] { [] }
        func search(_ query: SearchQuery, page: Int, pageSize: Int) -> NumberedPage<
            SearchProductSummary
        > {
            let items = [
                SearchProductSummary(
                    id: 1, title: "Xiaomi 17 Pro", subtitle: "旗舰性能与影像",
                    imageURL: nil, priceYuan: 4999, sold: 306),
                SearchProductSummary(
                    id: 2, title: "Xiaomi 17",
                    subtitle: "轻巧旗舰", imageURL: nil, priceYuan: 3999, sold: 653),
            ]
            return NumberedPage(items: items, page: page, size: pageSize, total: 2)
        }
    }
#endif
