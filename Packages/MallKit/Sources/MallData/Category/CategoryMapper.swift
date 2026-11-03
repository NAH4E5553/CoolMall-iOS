import Foundation
import MallCore

/// Applies the CATEGORY-01 field contract: required positive Int64 ids unique
/// across the whole flat list, non-blank names, integer sortNum (absent/null ->
/// 0 as the reference client does), and absolute-HTTPS-or-nil images. One bad
/// required field fails the whole read (`invalidPayload`) instead of dropping
/// nodes or fabricating navigation. Unknown parent ids and deeper nodes are
/// valid data; the snapshot builder decides what is displayable.
enum CategoryMapper {
    static func categories(from items: [CategoryDTO]) throws(CategoryLoadFailure) -> [CategoryNode]
    {
        var seen = Set<Int64>()
        var mapped: [CategoryNode] = []
        mapped.reserveCapacity(items.count)
        for item in items {
            guard item.id > 0 else { throw CategoryLoadFailure.invalidPayload }
            guard seen.insert(item.id).inserted else { throw CategoryLoadFailure.invalidPayload }
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CategoryLoadFailure.invalidPayload
            }
            mapped.append(
                CategoryNode(
                    id: item.id,
                    name: item.name,
                    parentID: item.parentId,
                    sortNum: item.sortNum ?? 0,
                    imageURL: imageURL(item.pic)
                )
            )
        }
        return mapped
    }

    /// Missing/null/empty or malformed text -> nil (placeholder); a valid string
    /// must already be an absolute HTTPS URL. Same approved image text rule as
    /// the H0 mapper, kept local so the H0 path is untouched.
    private static func imageURL(_ text: String?) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil
        else {
            return nil
        }
        return url
    }
}
