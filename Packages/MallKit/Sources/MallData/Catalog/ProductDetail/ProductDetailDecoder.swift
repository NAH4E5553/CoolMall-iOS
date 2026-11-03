import Foundation
import MallCore

private struct DetailDTO: Decodable {
    let goodsInfo: ProductDTO
    let coupon: [CouponDTO]?
    let comment: [ProductReviewDTO]?
}
private struct CouponDTO: Decodable {
    let id: Int64
    let title: String
    let description: String?
    let amount: Decimal
    let condition: CouponConditionDTO?
    let endTime: String?
}
private struct CouponConditionDTO: Decodable {
    let fullAmount: Decimal?
    private enum CodingKeys: String, CodingKey { case fullAmount }
    init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullAmount = nil
            } else {
                fullAmount = try JSONDecoder().decode(Self.self, from: Data(text.utf8)).fullAmount
            }
        } else {
            fullAmount = try decoder.container(keyedBy: CodingKeys.self)
                .decodeIfPresent(Decimal.self, forKey: .fullAmount)
        }
    }
}
private struct ProductDTO: Decodable {
    let id: Int64
    let title: String
    let subTitle: String?
    let price: Int64
    let sold: Int64
    let status: Int
    let mainPic: String?
    let pics: [String]?
    let contentPics: [String]?
}
private struct SpecificationDTO: Decodable {
    let id: Int64
    let goodsId: Int64
    let name: String
    let price: Int64
    let stock: Int64
    let images: [String]?
}

/// Strict identity and field validation for read-only goods, coupons and review summaries.
enum ProductDetailDecoder {
    private static func payload<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(EnvelopeHeader.self, from: data) else {
            throw ProductDetailLoadFailure.invalidResponse
        }
        guard header.code == 1000 else { throw ProductDetailLoadFailure.businessCode(header.code) }
        guard let envelope = try? decoder.decode(Envelope<T>.self, from: data),
            let body = envelope.data
        else { throw ProductDetailLoadFailure.invalidResponse }
        return body
    }

    static func detail(_ data: Data, productID: Int64) throws -> ProductDetailSnapshot {
        let detail = try payload(data, as: DetailDTO.self)
        let product = detail.goodsInfo
        guard productID > 0, product.id == productID,
            !product.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            product.price >= 0, product.sold >= 0, [0, 1].contains(product.status)
        else { throw ProductDetailLoadFailure.invalidResponse }
        let images = urls(product.pics)
        let fallback = urls(product.mainPic.map { [$0] })
        return ProductDetailSnapshot(
            id: product.id, title: product.title,
            subtitle: product.subTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            priceYuan: Decimal(product.price), sold: product.sold, isAvailable: product.status == 1,
            imageURLs: images.isEmpty ? fallback : images,
            contentImageURLs: urls(product.contentPics),
            coupons: try coupons(detail.coupon ?? []),
            reviews: try ProductReviewMapping.reviews(detail.comment ?? [], productID: productID))
    }

    static func specifications(_ data: Data, productID: Int64) throws -> [ProductSpecification] {
        let items = try payload(data, as: [SpecificationDTO].self)
        var seen = Set<Int64>()
        return try items.map { item in
            guard item.id > 0, productID > 0, item.goodsId == productID,
                seen.insert(item.id).inserted,
                !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                item.price >= 0, item.stock >= 0
            else { throw ProductDetailLoadFailure.invalidResponse }
            return ProductSpecification(
                id: item.id, productID: item.goodsId, name: item.name,
                priceYuan: Decimal(item.price), stock: item.stock, imageURLs: urls(item.images))
        }
    }

    private static func coupons(_ values: [CouponDTO]) throws -> [ProductDetailCoupon] {
        guard Set(values.map(\.id)).count == values.count else {
            throw ProductDetailLoadFailure.invalidResponse
        }
        return try values.map { value in
            guard value.id > 0,
                !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                value.amount >= 0, (value.condition?.fullAmount ?? 0) >= 0
            else {
                throw ProductDetailLoadFailure.invalidResponse
            }
            return ProductDetailCoupon(
                id: value.id, title: value.title,
                description: value.description ?? "", amountYuan: value.amount,
                minimumSpendYuan: value.condition?.fullAmount, endTime: value.endTime?.nilIfEmpty)
        }
    }

    private static func urls(_ values: [String]?) -> [URL] {
        (values ?? []).compactMap { value in
            guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
                url.user == nil, url.password == nil
            else { return nil }
            return url
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
