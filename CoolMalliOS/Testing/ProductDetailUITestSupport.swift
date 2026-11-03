#if DEBUG
    import Foundation
    import MallCore

    /// Opt-in, deterministic dependencies for the real detail entry. No network
    /// fallback, route mutation or alternate product screen.
    actor ProductDetailUITestService: ProductDetailLoading {
        private let mode: String
        private var detailReads = 0
        private var specificationReads = 0
        init(mode: String) { self.mode = mode }

        static func make(arguments: [String]) -> ProductDetailUITestService? {
            guard let index = arguments.firstIndex(of: "--ui-product-detail-fixture") else {
                return nil
            }
            let mode = index + 1 < arguments.count ? arguments[index + 1] : "invalid"
            return ProductDetailUITestService(mode: mode)
        }

        func loadDetail(productID: Int64) async throws -> ProductDetailSnapshot {
            detailReads += 1
            guard
                ["valid", "retry", "spec-retry", "empty-specs", "unavailable", "loading"].contains(
                    mode)
            else { throw ProductDetailLoadFailure.invalidConfiguration }
            if mode == "loading" {
                try await Task.sleep(for: .seconds(3600))
                throw CancellationError()
            }
            if mode == "retry" && detailReads == 1 {
                throw ProductDetailLoadFailure.networkUnavailable
            }
            return ProductDetailSnapshot(
                id: productID, title: "详情夹具商品 \(productID)", subtitle: "只读商品与规格草稿",
                priceYuan: 3999, sold: 306, isAvailable: mode != "unavailable",
                imageURLs: [
                    "https://detail-fixture.invalid/1.png", "https://detail-fixture.invalid/2.png",
                ].compactMap(URL.init(string:)),
                contentImageURLs: [
                    "https://detail-fixture.invalid/content-1.png",
                    "https://detail-fixture.invalid/content-2.png",
                ].compactMap(URL.init(string:)),
                coupons: [
                    ProductDetailCoupon(
                        id: 860001, title: "【满减券】小米精选满299减30元", description: "小米商城精选商品可用",
                        amountYuan: 30, minimumSpendYuan: 299, endTime: "2030-01-01 00:00:00"),
                    ProductDetailCoupon(
                        id: 860002, title: "【满减券】小米家电满999减80元", description: "电视、洗衣机、清洁电器可用",
                        amountYuan: 80, minimumSpendYuan: 999, endTime: "2030-01-01 00:00:00"),
                    ProductDetailCoupon(
                        id: 860003, title: "【满减券】小米数码满1999减150元", description: "手机、平板、电脑、穿戴可用",
                        amountYuan: 150, minimumSpendYuan: 1999, endTime: "2030-01-01 00:00:00"),
                ],
                reviews: (1...3).map { index in
                    ProductDetailReview(
                        id: Int64(index), productID: productID, content: "评价内容\(index)",
                        starCount: index == 2 ? 4 : 5, nickname: "用户\(index)", avatarURL: nil,
                        imageURLs: [])
                })
        }

        func loadSpecifications(productID: Int64) async throws -> [ProductSpecification] {
            specificationReads += 1
            if mode == "spec-retry" && specificationReads == 1 {
                throw ProductDetailLoadFailure.timeout
            }
            if mode == "empty-specs" { return [] }
            return [
                ProductSpecification(
                    id: 1, productID: productID, name: "黑色 256GB",
                    priceYuan: 3999, stock: 2, imageURLs: []),
                ProductSpecification(
                    id: 2, productID: productID, name: "银色 512GB",
                    priceYuan: 4999, stock: 0, imageURLs: []),
                ProductSpecification(
                    id: 3, productID: productID, name: "蓝色 256GB",
                    priceYuan: 4099, stock: 1, imageURLs: []),
            ]
        }
    }
#endif
