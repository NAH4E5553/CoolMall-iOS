import MallCore
import Testing
@testable import CatalogFeature

struct HomeCatalogNavigationTests {
    @Test func eachHomeCategoryUsesOnlyItsOwnDirectChildren() {
        let categories = (1...10).flatMap { index in
            [
                HomeCategory(id: Int64(index), name: "一级", parentID: nil, imageURL: nil),
                HomeCategory(
                    id: Int64(index + 100), name: "二级", parentID: Int64(index), imageURL: nil),
                HomeCategory(
                    id: Int64(index + 200), name: "二级", parentID: Int64(index), imageURL: nil),
                HomeCategory(
                    id: Int64(index + 300), name: "更深层", parentID: Int64(index + 100), imageURL: nil
                ),
            ]
        }
        for index in 1...10 {
            #expect(
                HomeCategorySearchSelection.ids(for: Int64(index), in: categories) == [
                    Int64(index + 100), Int64(index + 200),
                ])
        }
        #expect(HomeCategorySearchSelection.ids(for: 99, in: categories) == [99])
        #expect(HomeCategorySearchSelection.ids(for: 0, in: categories).isEmpty)
    }
}
