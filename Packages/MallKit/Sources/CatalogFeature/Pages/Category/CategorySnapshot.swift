import MallCore

/// One left-hand root and the DIRECT children shown in its right-hand section.
/// Deeper nodes (a child of a child) and nodes whose parent is not a root stay
/// in the flat payload but are not part of this display projection, matching
/// the reference screen: the tree is recursive there, but only `children` of a
/// root are rendered.
struct CategoryGroup: Identifiable, Equatable {
    let root: CategoryNode
    let children: [CategoryNode]
    var id: Int64 { root.id }
}

/// Immutable display projection of one successful read. The page model owns the
/// instance; views only read it.
struct CategorySnapshot: Equatable {
    let groups: [CategoryGroup]

    var isEmpty: Bool { groups.isEmpty }
    var rootCount: Int { groups.count }
    var directChildCount: Int { groups.reduce(0) { $0 + $1.children.count } }

    func index(ofRoot id: Int64) -> Int? {
        groups.firstIndex { $0.root.id == id }
    }

    func contains(rootID: Int64) -> Bool {
        index(ofRoot: rootID) != nil
    }

    /// Reference ordering: ALL nodes are sorted by `sortNum` ascending with the
    /// payload order as the tie-break (the reference client's `sortedBy` is
    /// stable; Swift's `sort` is not, so the original offset is explicit), then
    /// roots (`parentId == nil`) become groups and every other node is grouped
    /// under its parent id. Equal `sortNum` values therefore keep payload order.
    static func build(from categories: [CategoryNode]) -> CategorySnapshot {
        let ordered =
            categories.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.sortNum != rhs.element.sortNum {
                    return lhs.element.sortNum < rhs.element.sortNum
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        var childrenByParent: [Int64: [CategoryNode]] = [:]
        var roots: [CategoryNode] = []
        for category in ordered {
            if let parentID = category.parentID {
                childrenByParent[parentID, default: []].append(category)
            } else {
                roots.append(category)
            }
        }

        return CategorySnapshot(
            groups: roots.map { root in
                CategoryGroup(root: root, children: childrenByParent[root.id] ?? [])
            }
        )
    }
}
