import Foundation
import MallCore
import Observation

/// Page-owned read state and uncommitted SKU/quantity draft. Nothing writes
/// the cart. Structured View tasks own I/O; generations reject late responses.
@MainActor @Observable
final class ProductDetailViewModel {
    enum DetailState: Equatable {
        case idle, loading
        case ready(ProductDetailSnapshot)
        case failed(ProductDetailLoadFailure)
    }
    enum SpecificationState: Equatable {
        case idle, loading, empty
        case ready([ProductSpecification])
        case failed(ProductDetailLoadFailure)
    }
    let productID: Int64
    private let loader: any ProductDetailLoading
    private(set) var detailState: DetailState = .idle
    private(set) var specificationState: SpecificationState = .idle
    private(set) var detailAttempt = 0
    private(set) var specificationAttempt = 0
    private(set) var selectedID: Int64?
    private(set) var quantity: Int64 = 1
    private(set) var isGrid = true
    private var active = false
    private var detailGeneration = 0
    private var specificationGeneration = 0

    init(productID: Int64, loader: any ProductDetailLoading) {
        self.productID = productID; self.loader = loader
    }

    var detail: ProductDetailSnapshot? {
        if case .ready(let value) = detailState { value } else { nil }
    }
    var specifications: [ProductSpecification] {
        if case .ready(let values) = specificationState { values } else { [] }
    }
    var selected: ProductSpecification? { specifications.first { $0.id == selectedID } }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if !value {
            detailGeneration += 1; closeSpecifications()
            if case .loading = detailState { detailState = .idle }
        }
    }

    func loadDetail() async {
        guard active, !Task.isCancelled, case .idle = detailState else { return }
        guard productID > 0 else { detailState = .failed(.invalidProductID); return }
        detailGeneration += 1
        let generation = detailGeneration
        detailState = .loading
        do {
            let result = try await loader.loadDetail(productID: productID)
            guard active, generation == detailGeneration else { return }
            try Task.checkCancellation()
            guard result.id == productID else { throw ProductDetailLoadFailure.invalidResponse }
            detailState = .ready(result)
        } catch {
            guard active, generation == detailGeneration else { return }
            detailState =
                (error is CancellationError || Task.isCancelled)
                ? .idle : .failed((error as? ProductDetailLoadFailure) ?? .invalidResponse)
        }
    }

    func retryDetail() {
        guard active, case .failed = detailState else { return }
        detailGeneration += 1; detailState = .idle; detailAttempt += 1
    }

    func loadSpecifications() async {
        guard active, detail?.isAvailable == true, !Task.isCancelled,
            case .idle = specificationState
        else { return }
        specificationGeneration += 1
        let generation = specificationGeneration
        specificationState = .loading
        do {
            let result = try await loader.loadSpecifications(productID: productID)
            guard active, generation == specificationGeneration else { return }
            try Task.checkCancellation()
            guard Set(result.map(\.id)).count == result.count,
                result.allSatisfy({
                    $0.id > 0 && $0.productID == productID && $0.stock >= 0 && $0.priceYuan >= 0
                })
            else { throw ProductDetailLoadFailure.invalidResponse }
            specificationState = result.isEmpty ? .empty : .ready(result)
        } catch {
            guard active, generation == specificationGeneration else { return }
            specificationState =
                (error is CancellationError || Task.isCancelled)
                ? .idle : .failed((error as? ProductDetailLoadFailure) ?? .invalidResponse)
        }
    }

    func closeSpecifications() {
        specificationGeneration += 1
        if case .loading = specificationState { specificationState = .idle }
        // Dismissal preserves successful cache/selection/quantity (PRD-003).
    }

    func retrySpecifications() {
        guard active else { return }
        switch specificationState {
        case .failed, .empty:
            specificationGeneration += 1; specificationState = .idle; specificationAttempt += 1
        default: break
        }
    }

    func select(_ id: Int64) {
        guard let spec = specifications.first(where: { $0.id == id }) else { return }
        selectedID = selectedID == id ? nil : id
        // A user-selected lower-stock SKU constrains only this visible draft.
        // No committed cart quantity or server stock is modified.
        if selectedID != nil, spec.stock > 0 { quantity = min(quantity, spec.stock) }
    }
    func changeQuantity(by delta: Int64) {
        guard let selected, selected.stock > 0 else { return }
        if delta == 1, quantity < selected.stock { quantity += 1 }
        if delta == -1, quantity > 1 { quantity -= 1 }
    }
    func toggleLayout() { isGrid.toggle() }
}
