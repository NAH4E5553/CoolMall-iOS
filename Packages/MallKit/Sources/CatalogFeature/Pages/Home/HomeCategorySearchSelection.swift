import MallCore

/// Match the reference home's direct-child filter, never broaden an empty mapping to all goods.
enum HomeCategorySearchSelection {
    static func ids(for categoryID: Int64, in categories: [HomeCategory]) -> [Int64] {
        guard categoryID > 0 else { return [] }
        let children = categories.filter { $0.parentID == categoryID && $0.id > 0 }.map(\.id)
        return children.isEmpty ? [categoryID] : children
    }
}
