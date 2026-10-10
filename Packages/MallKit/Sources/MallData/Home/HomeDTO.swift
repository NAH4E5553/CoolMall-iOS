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
}

struct HomeCouponDTO: Decodable {
    let id: Int64
    let title: String
}
