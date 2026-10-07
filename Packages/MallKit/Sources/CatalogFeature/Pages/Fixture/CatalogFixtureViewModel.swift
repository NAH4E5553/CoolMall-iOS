import MallCore
import Observation

/// Entry View identity owns this model. .task owns each load and cancels on departure.
/// Result state is a projection; generation prevents replaced/cancelled work from publishing.
@MainActor @Observable
final class CatalogFixtureViewModel {
    enum State: Equatable { case idle; case loading; case ready(Product); case failed }
    private(set) var state: State = .idle
    private let products: any ProductLoading
    private var generation = 0
    init(products: any ProductLoading) { self.products = products }
    func load() async {
        generation += 1
        let request = generation
        state = .loading
        do {
            let product = try await products.product(id: 1)
            guard request == generation else { return }
            try Task.checkCancellation()
            state = .ready(product)
        } catch is CancellationError {
            if request == generation { state = .idle }
        } catch {
            if request == generation { state = Task.isCancelled ? .idle : .failed }
        }
    }
}
