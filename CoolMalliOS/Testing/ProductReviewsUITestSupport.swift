#if DEBUG
    import Foundation
    import MallCore

    /// Only explicit UI-test launches replace the real anonymous reviews service.
    actor ProductReviewsUITestService: ProductReviewsLoading {
        let mode: String
        private var firstPageReads = 0
        private var secondPageReads = 0
        init(mode: String) { self.mode = mode }
        static func make(arguments: [String]) -> ProductReviewsUITestService? {
            guard let index = arguments.firstIndex(of: "--ui-product-reviews-fixture") else {
                return nil
            }
            return ProductReviewsUITestService(
                mode: arguments.indices.contains(index + 1) ? arguments[index + 1] : "invalid")
        }
        func loadReviews(productID: Int64, page: Int, pageSize: Int) async throws
            -> ProductReviewPage
        {
            guard pageSize == 10,
                ["valid", "retry", "append-retry", "refresh-failure", "empty", "loading"].contains(
                    mode)
            else {
                throw ProductDetailLoadFailure.invalidConfiguration
            }
            if page == 1 { firstPageReads += 1 } else { secondPageReads += 1 }
            if mode == "loading" {
                try await Task.sleep(for: .seconds(3600)); throw CancellationError()
            }
            if mode == "retry", firstPageReads == 1 {
                throw ProductDetailLoadFailure.networkUnavailable
            }
            if mode == "append-retry", page == 2, secondPageReads == 1 {
                throw ProductDetailLoadFailure.timeout
            }
            if mode == "refresh-failure", page == 1, firstPageReads > 1 {
                throw ProductDetailLoadFailure.networkUnavailable
            }
            if mode == "empty", firstPageReads == 1 {
                return ProductReviewPage(items: [], nextPage: nil)
            }
            if page == 1 {
                return ProductReviewPage(
                    items: [
                        review(1, productID, firstPageReads > 1 ? "刷新后的评价" : "第一条评价", pictures: 2),
                        review(2, productID, "第二条评价", pictures: 3),
                        review(3, productID, "第三条评价", pictures: 0),
                    ], nextPage: 2)
            }
            return ProductReviewPage(
                items: [
                    review(3, productID, "第三条更新", pictures: 0),
                    review(4, productID, "末页评价", pictures: 1),
                ], nextPage: nil)
        }
        private func review(_ id: Int64, _ productID: Int64, _ title: String, pictures: Int)
            -> ProductDetailReview
        {
            ProductDetailReview(
                id: id, productID: productID,
                content: title + "：外观精致，机身做工细致，重量控制得好，长时间使用也很舒服。屏幕在强光下清晰可见，电池能够满足正常使用。",
                starCount: id == 2 ? 4 : 5, nickname: id == 1 ? "121****50" : "评价用户\(id)",
                avatarURL: nil,
                imageURLs: (0..<pictures).compactMap {
                    URL(string: "https://reviews-fixture.invalid/\(id)-\($0).png")
                },
                createdAt: "2026-07-15 21:24:07")
        }
    }
#endif
