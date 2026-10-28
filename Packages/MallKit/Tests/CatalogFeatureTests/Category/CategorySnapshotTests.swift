import Foundation
import MallCore
@testable import CatalogFeature
import Testing

/// CATEGORY-01 display projection over the flat payload: sortNum order with
/// payload-order tie-break, root/child grouping, direct children only, and
/// the abnormal branches that stay non-displayable instead of being guessed
/// into navigation.
struct CategorySnapshotTests {
    private func node(
        _ id: Int64, _ name: String, _ parent: Int64?, _ sortNum: Int, pic: String? = nil
    ) -> CategoryNode {
        CategoryNode(
            id: id, name: name, parentID: parent, sortNum: sortNum,
            imageURL: pic.flatMap { URL(string: $0) })
    }

    @Test func rootsAndDirectChildrenUseSortNumWithStablePayloadTieBreak() {
        let categories = [
            node(3, "根B", nil, 2),
            node(1, "根A", nil, 1),
            node(12, "子2", 1, 2),
            node(11, "子1", 1, 1),
            node(21, "根C", nil, 2),
            node(31, "子3", 3, 1),
        ]
        let snapshot = CategorySnapshot.build(from: categories)
        #expect(snapshot.groups.map(\.root.id) == [1, 3, 21])
        #expect(snapshot.groups.map(\.root.name) == ["根A", "根B", "根C"])
        #expect(snapshot.groups[0].children.map(\.id) == [11, 12])
        #expect(snapshot.groups[1].children.map(\.id) == [31])
        #expect(snapshot.groups[2].children.isEmpty)
        #expect(snapshot.rootCount == 3)
        #expect(snapshot.directChildCount == 3)
    }

    @Test func deeperNodesAndUnknownParentsStayUndisplayed() {
        let categories = [
            node(1, "根", nil, 1),
            node(11, "直接子", 1, 1),
            node(111, "孙节点", 11, 1),
            node(99, "未知父", 999, 1),
        ]
        let snapshot = CategorySnapshot.build(from: categories)
        #expect(snapshot.groups.count == 1)
        #expect(snapshot.groups[0].children.map(\.id) == [11])
        #expect(snapshot.directChildCount == 1)
        #expect(!snapshot.contains(rootID: 111))
        #expect(!snapshot.contains(rootID: 99))
    }

    @Test func rootWithoutChildrenKeepsItsGroupAndEmptyListIsEmpty() {
        let withEmptyRoot = CategorySnapshot.build(from: [node(1, "空根", nil, 1)])
        #expect(withEmptyRoot.groups.count == 1)
        #expect(withEmptyRoot.groups[0].children.isEmpty)

        let empty = CategorySnapshot.build(from: [])
        #expect(empty.isEmpty)
        #expect(empty.rootCount == 0)
        #expect(empty.directChildCount == 0)
        #expect(empty.index(ofRoot: 1) == nil)
    }

    @Test func indexLookupMatchesRootOrder() {
        let snapshot = CategorySnapshot.build(from: [
            node(2, "B", nil, 2), node(1, "A", nil, 1), node(3, "C", nil, 3),
        ])
        #expect(snapshot.index(ofRoot: 1) == 0)
        #expect(snapshot.index(ofRoot: 2) == 1)
        #expect(snapshot.index(ofRoot: 3) == 2)
        #expect(snapshot.contains(rootID: 3))
    }
}
