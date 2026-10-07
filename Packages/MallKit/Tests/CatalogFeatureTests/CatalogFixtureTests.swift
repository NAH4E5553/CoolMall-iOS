@testable import CatalogFeature
import MallCore
import Testing

private enum Failure: Error { case fixture }
private struct Products: ProductLoading {
    var fails = false
    func product(id: Int64) async throws -> Product {
        if fails { throw Failure.fixture }
        return Product(id: id, title: "fixture")
    }
}

/// Intentionally ignores cancellation so the consumer must reject stale completions.
private actor ControlledProducts: ProductLoading {
    private var requests: [CheckedContinuation<Product, any Error>] = []
    var count: Int { requests.count }
    func product(id: Int64) async throws -> Product {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
    func complete(_ index: Int, title: String) {
        requests[index].resume(returning: Product(id: 1, title: title))
    }
}

@Test @MainActor func successAndFailure() async {
    let success = CatalogFixtureViewModel(products: Products())
    await success.load()
    #expect(success.state == .ready(Product(id: 1, title: "fixture")))
    let failed = CatalogFixtureViewModel(products: Products(fails: true))
    await failed.load()
    #expect(failed.state == .failed)
}

@Test @MainActor func replacedLoadCannotOverwriteNewResult() async {
    let products = ControlledProducts()
    let model = CatalogFixtureViewModel(products: products)
    let old = Task { await model.load() }
    while await products.count < 1 { await Task.yield() }
    let latest = Task { await model.load() }
    while await products.count < 2 { await Task.yield() }
    await products.complete(1, title: "new")
    await latest.value
    await products.complete(0, title: "old")
    await old.value
    #expect(model.state == .ready(Product(id: 1, title: "new")))
}

@Test @MainActor func cancelledLoadReturnsIdle() async {
    let products = ControlledProducts()
    let model = CatalogFixtureViewModel(products: products)
    let load = Task { await model.load() }
    while await products.count < 1 { await Task.yield() }
    load.cancel()
    await products.complete(0, title: "cancelled")
    await load.value
    #expect(model.state == .idle)
}
