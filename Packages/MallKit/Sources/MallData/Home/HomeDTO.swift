import Foundation

/// Raw payload DTOs (internal). Optional fields mirror the backend model's
/// nullability; every approved H0 field rule is enforced by HomeMapper, and
/// unknown fields are ignored by the decoder.
struct HomeDTO: Decodable {
    var banner: [HomeBannerDTO]?
    var category: [HomeCategoryDTO]?
    var categoryAll: [HomeCategoryDTO]?
    var flashSale: [HomeProductDTO]?
    var recommend: [HomeProductDTO]?
    var goods: [HomeProductDTO]?
    var coupon: [HomeCouponDTO]?
}

struct HomeBannerDTO: Decodable {
    let id: Int64
    let description: String?
    let pic: String?
}

struct HomeCategoryDTO: Decodable {
    let id: Int64
    let name: String
    let parentId: Int64?
    let pic: String?
}

struct HomeProductDTO: Decodable {
    let id: Int64
    let title: String
    let subTitle: String?
    let mainPic: String?
    let price: Int64
    let sold: Int64?
}

struct HomeCouponDTO: Decodable {
    let id: Int64
    let title: String
    let description: String?
    let amount: Decimal?
    let endTime: String?
    let condition: HomeCouponConditionDTO?
}
struct HomeCouponConditionDTO: Decodable {
    let fullAmount: Decimal?
    private enum CodingKeys: String, CodingKey { case fullAmount }
    init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            fullAmount =
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : try JSONDecoder().decode(Self.self, from: Data(text.utf8)).fullAmount
        } else {
            fullAmount = try decoder.container(keyedBy: CodingKeys.self)
                .decodeIfPresent(Decimal.self, forKey: .fullAmount)
        }
    }
}
