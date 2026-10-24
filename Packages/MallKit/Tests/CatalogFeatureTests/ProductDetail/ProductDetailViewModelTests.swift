import MallCore
@testable import CatalogFeature
import Testing

@MainActor
struct ProductDetailViewModelTests {
    static func product(_ id: Int64 = 830001, available: Bool = true) -> ProductDetailSnapshot {
        ProductDetailSnapshot(
            id: id, title: "真实只读夹具", subtitle: nil, priceYuan: 3999,
            sold: 0, isAvailable: available, imageURLs: [], contentImageURLs: [])
    }
    static func spec(_ id: Int64 = 1, stock: Int64 = 2, product: Int64 = 830001)
        -> ProductSpecification
    {
        ProductSpecification(
            id: id, productID: product, name: "规格 \(id)", priceYuan: 4000,
            stock: stock, imageURLs: [])
    }

    @MainActor
    final class Service: ProductDetailLoading {
        enum DetailStep { case value(ProductDetailSnapshot), fail(ProductDetailLoadFailure), gate }
        enum SpecStep { case value([ProductSpecification]), fail(ProductDetailLoadFailure), gate }
        var details: [DetailStep]
        var specs: [SpecStep]
        private(set) var detailCalls = 0
        private(set) var specCalls = 0
        var detailGates: [CheckedContinuation<ProductDetailSnapshot, Error>] = []
        var specGates: [CheckedContinuation<[ProductSpecification], Error>] = []
        init(
            _ details: [DetailStep] = [.value(product())],
            specs: [SpecStep] = [.value([spec()])]
        ) { self.details = details; self.specs = specs }

        func loadDetail(productID: Int64) async throws -> ProductDetailSnapshot {
            detailCalls += 1
            guard !details.isEmpty else { throw ProductDetailLoadFailure.invalidResponse }
            switch details.removeFirst() {
            case .value(let value): return value
            case .fail(let failure): throw failure
            case .gate: return try await withCheckedThrowingContinuation { detailGates.append($0) }
            }
        }
        func loadSpecifications(productID: Int64) async throws -> [ProductSpecification] {
            specCalls += 1
            guard !specs.isEmpty else { throw ProductDetailLoadFailure.invalidResponse }
            switch specs.removeFirst() {
            case .value(let value): return value
            case .fail(let failure): throw failure
            case .gate: return try await withCheckedThrowingContinuation { specGates.append($0) }
            }
        }
    }
    func loaded(_ service: Service) async -> ProductDetailViewModel {
        let model = ProductDetailViewModel(productID: 830001, loader: service)
        model.setActive(true); await model.loadDetail(); return model
    }
    func wait(_ predicate: () -> Bool) async {
        for _ in 0..<1000 {
            if predicate() { return }
            await Task.yield()
        }
        Issue.record("gate did not open")
    }

    @Test func invalidIDNeverCallsService() async {
        let service = Service()
        let model = ProductDetailViewModel(productID: 0, loader: service)
        model.setActive(true); await model.loadDetail()
        #expect(model.detailState == .failed(.invalidProductID))
        #expect(service.detailCalls == 0)
    }

    @Test func inactiveThenReadyDoesNotRereadOnResume() async {
        let service = Service()
        let model = ProductDetailViewModel(productID: 830001, loader: service)
        await model.loadDetail(); #expect(service.detailCalls == 0)
        model.setActive(true); await model.loadDetail()
        model.setActive(false); model.setActive(true); await model.loadDetail()
        #expect(model.detail == Self.product())
        #expect(service.detailCalls == 1)
    }

    @Test func detailFailureRetriesOnlyOnExplicitIntent() async {
        let service = Service([.fail(.timeout), .value(Self.product())])
        let model = await loaded(service)
        #expect(model.detailState == .failed(.timeout))
        await model.loadDetail(); #expect(service.detailCalls == 1)
        model.retryDetail(); await model.loadDetail()
        #expect(model.detail == Self.product())
        #expect(service.detailCalls == 2)
    }

    @Test(arguments: [false, true])
    func lateDetailSuccessAndErrorCannotOverwriteNewGeneration(_ oldFails: Bool) async {
        let service = Service([.gate, .value(Self.product())])
        let model = ProductDetailViewModel(productID: 830001, loader: service)
        model.setActive(true)
        let old = Task { await model.loadDetail() }
        await wait { service.detailGates.count == 1 }
        #expect(model.detailState == .loading)
        model.setActive(false); old.cancel()
        model.setActive(true); await model.loadDetail()
        let gate = service.detailGates.removeFirst()
        if oldFails {
            gate.resume(throwing: ProductDetailLoadFailure.networkUnavailable)
        } else {
            gate.resume(returning: Self.product(2))
        }
        await old.value
        #expect(model.detail == Self.product())
        #expect(service.detailCalls == 2)
    }

    @Test func cancelledCurrentReadIsIdleNotError() async {
        let service = Service([.gate])
        let model = ProductDetailViewModel(productID: 830001, loader: service)
        model.setActive(true)
        let read = Task { await model.loadDetail() }
        await wait { service.detailGates.count == 1 }
        read.cancel()
        service.detailGates.removeFirst().resume(throwing: CancellationError())
        await read.value
        #expect(model.detailState == .idle)
    }

    @Test func mismatchedDetailFails() async {
        let model = await loaded(Service([.value(Self.product(2))]))
        #expect(model.detailState == .failed(.invalidResponse))
    }

    @Test func unavailableDetailNeverLoadsSpecifications() async {
        let service = Service([.value(Self.product(available: false))])
        let model = await loaded(service)
        await model.loadSpecifications()
        #expect(service.specCalls == 0)
    }

    @Test func specificationErrorDoesNotEraseDetailAndRetryRecovers() async {
        let service = Service(specs: [.fail(.networkUnavailable), .value([Self.spec()])])
        let model = await loaded(service)
        await model.loadSpecifications()
        #expect(model.specificationState == .failed(.networkUnavailable))
        #expect(model.detail == Self.product())
        model.retrySpecifications(); await model.loadSpecifications()
        #expect(model.specifications == [Self.spec()])
    }

    @Test func emptySpecificationsAreDistinctAndExplicitlyReloadable() async {
        let service = Service(specs: [.value([]), .value([Self.spec()])])
        let model = await loaded(service)
        await model.loadSpecifications()
        #expect(model.specificationState == .empty)
        await model.loadSpecifications(); #expect(service.specCalls == 1)
        model.retrySpecifications(); await model.loadSpecifications()
        #expect(model.specifications.count == 1)
    }

    @Test(arguments: [false, true])
    func closingSheetRejectsLateSpecificationsWithoutErasingFreshCache(_ oldFails: Bool) async {
        let service = Service(specs: [.gate, .value([Self.spec()])])
        let model = await loaded(service)
        let old = Task { await model.loadSpecifications() }
        await wait { service.specGates.count == 1 }
        model.closeSpecifications(); old.cancel()
        await model.loadSpecifications()
        let gate = service.specGates.removeFirst()
        if oldFails {
            gate.resume(throwing: ProductDetailLoadFailure.timeout)
        } else {
            gate.resume(returning: [Self.spec(99)])
        }
        await old.value
        #expect(model.specifications == [Self.spec()])
    }

    @Test func sheetCloseReopenRetainsDraftAndCacheButNewPageResets() async {
        let service = Service()
        let model = await loaded(service)
        await model.loadSpecifications()
        model.select(1); model.changeQuantity(by: 1); model.toggleLayout()
        model.closeSpecifications(); await model.loadSpecifications()
        #expect(model.selectedID == 1); #expect(model.quantity == 2); #expect(!model.isGrid)
        #expect(service.specCalls == 1); #expect(service.detailCalls == 1)
        let fresh = ProductDetailViewModel(productID: 830001, loader: service)
        #expect(fresh.selectedID == nil); #expect(fresh.quantity == 1)
        let other = ProductDetailViewModel(productID: 2, loader: service)
        #expect(other.selectedID == nil); #expect(other.specifications.isEmpty)
    }

    @Test func singleSelectionToggleAndStockBounds() async {
        let model = await loaded(
            Service(specs: [.value([Self.spec(), Self.spec(2, stock: 0), Self.spec(3, stock: 1)])]))
        await model.loadSpecifications()
        model.changeQuantity(by: 1); #expect(model.quantity == 1)
        model.select(1); model.changeQuantity(by: 1); model.changeQuantity(by: 1)
        #expect(model.quantity == 2)
        model.select(1); #expect(model.selectedID == nil)
        #expect(model.detail?.priceYuan == 3999)
        model.select(3); #expect(model.quantity == 1)
        model.select(2); model.changeQuantity(by: 1); #expect(model.quantity == 1)
        #expect(model.selected?.stock == 0)
        model.select(999); #expect(model.selectedID == 2)
        model.select(1); model.changeQuantity(by: -1); #expect(model.quantity == 1)
    }

    @Test func mismatchedDuplicateAndNegativeStockSpecificationAreRejected() async {
        for invalid in [
            [Self.spec(product: 2)], [Self.spec(), Self.spec()], [Self.spec(stock: -1)],
        ] {
            let model = await loaded(Service(specs: [.value(invalid)]))
            await model.loadSpecifications()
            #expect(model.specificationState == .failed(.invalidResponse))
        }
    }
}
