import Foundation
import MallCore

struct ProductReviewDTO: Decodable {
    let id: Int64
    let goodsId: Int64
    let content: String
    let starCount: Int
    let nickName: String?
    let avatarUrl: String?
    let pics: [String]?
    let createTime: String?
}

enum ProductReviewMapping {
    static func reviews(_ values: [ProductReviewDTO], productID: Int64) throws
        -> [ProductDetailReview]
    {
        guard Set(values.map(\.id)).count == values.count else {
            throw ProductDetailLoadFailure.invalidResponse
        }
        return try values.map { value in
            guard value.id > 0, value.goodsId == productID, (0...5).contains(value.starCount) else {
                throw ProductDetailLoadFailure.invalidResponse
            }
            return ProductDetailReview(
                id: value.id, productID: value.goodsId, content: value.content,
                starCount: value.starCount,
                nickname: value.nickName?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty,
                avatarURL: urls(value.avatarUrl.map { [$0] }).first, imageURLs: urls(value.pics),
                createdAt: value.createTime?.nonempty)
        }
    }
    private static func urls(_ values: [String]?) -> [URL] {
        (values ?? []).compactMap { text in
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
                url.user == nil, url.password == nil
            else { return nil }
            return url
        }
    }
}
private extension String { var nonempty: String? { isEmpty ? nil : self } }
