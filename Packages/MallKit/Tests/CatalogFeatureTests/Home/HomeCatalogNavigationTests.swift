import MallCore
import Testing
@testable import CatalogFeature

struct HomeCatalogNavigationTests {
    @Test func eachHomeCategoryUsesOnlyItsOwnDirectChildren() {
        let categories: [HomeCategory] = (1...10).flatMap { (index: Int) -> [HomeCategory] in
            let id = Int64(index)
            return [
                HomeCategory(id: id, name: "一级", parentID: nil, imageURL: nil),
                HomeCategory(
                    id: id + 100, name: "二级", parentID: id, imageURL: nil),
                HomeCategory(
                    id: id + 200, name: "二级", parentID: id, imageURL: nil),
                HomeCategory(
                    id: id + 300, name: "更深层", parentID: id + 100, imageURL: nil
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
