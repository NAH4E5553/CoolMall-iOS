import MallCore
import Observation

@MainActor @Observable
final class CartBadgeViewModel {
    private(set) var count: Int64?
    func observe(_ store: any ShoppingCart) async {
        count = nil
        do {
            let stream = try await store.observe()
            for await value in stream {
                guard !Task.isCancelled else { return }
                count = try value.itemCount()
            }
        } catch { if !Task.isCancelled { count = nil } }
    }
}
