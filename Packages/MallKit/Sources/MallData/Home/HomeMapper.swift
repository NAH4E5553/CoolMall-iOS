import Foundation
import MallCore

/// Applies the approved H0 v0.2 field contract (PRODUCT_SPEC 8.11.2):
/// required positive IDs unique per section, non-blank titles/names, integer
/// non-negative prices as exact yuan Decimals, absolute-HTTPS-or-nil image
/// URLs; one bad required field fails the whole read (invalidPayload) — no
/// silent drops, defaults or zero prices.
enum HomeMapper {
    static func snapshot(from dto: HomeDTO) throws(HomeLoadFailure) -> HomeSnapshot {
        HomeSnapshot(
            banners: try banners(dto.banner),
            categories: try categories(dto.category),
            allCategories: try categories(dto.categoryAll),
            featured: try products(dto.flashSale),
            recommendations: try products(dto.recommend),
            goods: try products(dto.goods),
            coupons: try coupons(dto.coupon)
        )
    }

    private static func banners(_ items: [HomeBannerDTO]?) throws(HomeLoadFailure) -> [HomeBanner] {
        guard let items else { return [] }
        var seen = Set<Int64>()
        var mapped: [HomeBanner] = []
        for item in items {
            try validateID(item.id, seen: &seen)
            mapped.append(
                HomeBanner(
                    id: item.id, description: item.description ?? "", imageURL: imageURL(item.pic))
            )
        }
        return mapped
    }

    private static func categories(_ items: [HomeCategoryDTO]?) throws(HomeLoadFailure)
        -> [HomeCategory]
    {
        guard let items else { return [] }
        var seen = Set<Int64>()
        var mapped: [HomeCategory] = []
        for item in items {
            try validateID(item.id, seen: &seen)
            mapped.append(
                HomeCategory(
                    id: item.id,
                    name: try nonBlank(item.name, field: "category.name"),
                    parentID: item.parentId,
                    imageURL: imageURL(item.pic)
                )
            )
        }
        return mapped
    }

    private static func products(_ items: [HomeProductDTO]?) throws(HomeLoadFailure)
        -> [HomeProductSummary]
    {
        guard let items else { return [] }
        var seen = Set<Int64>()
        var mapped: [HomeProductSummary] = []
        for item in items {
            try validateID(item.id, seen: &seen)
            guard item.price >= 0 else { throw HomeLoadFailure.invalidPayload }
            mapped.append(
                HomeProductSummary(
                    id: item.id,
                    title: try nonBlank(item.title, field: "product.title"),
                    subtitle: item.subTitle,
                    imageURL: imageURL(item.mainPic),
                    priceYuan: Decimal(item.price)
                )
            )
        }
        return mapped
    }

    private static func coupons(_ items: [HomeCouponDTO]?) throws(HomeLoadFailure)
        -> [HomeCouponSummary]
    {
        guard let items else { return [] }
        var seen = Set<Int64>()
        var mapped: [HomeCouponSummary] = []
        for item in items {
            try validateID(item.id, seen: &seen)
            mapped.append(
                HomeCouponSummary(
                    id: item.id, title: try nonBlank(item.title, field: "coupon.title")))
        }
        return mapped
    }

    private static func validateID(_ id: Int64, seen: inout Set<Int64>) throws(HomeLoadFailure) {
        guard id > 0 else { throw HomeLoadFailure.invalidPayload }
        guard seen.insert(id).inserted else { throw HomeLoadFailure.invalidPayload }
    }

    private static func nonBlank(_ text: String, field: String) throws(HomeLoadFailure) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HomeLoadFailure.invalidPayload
        }
        return text
    }

    /// Missing/null/empty or malformed text → nil (placeholder); a valid
    /// string must already be an absolute HTTPS URL — no http rewrite, no
    /// relative resolution, no custom schemes.
    private static func imageURL(_ text: String?) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil
        else {
            return nil
        }
        return url
    }
}
