import Foundation
import MallCore
import Observation

@MainActor @Observable final class FootprintPreviewViewModel {
    private let store: any FootprintBrowsing
    private(set) var items: [FootprintItem] = []
    private(set) var error: String?
    private(set) var loaded = false
    private var generation = 0
    init(store: any FootprintBrowsing) { self.store = store }
    func observe() async {
        generation += 1; let epoch = generation
        do {
            let stream = try await store.changes()
            for await _ in stream {
                let page = try await store.page(offset: 0, limit: 8)
                try Task.checkCancellation(); guard generation == epoch else { return }
                items = page.items; loaded = true; error = nil
            }
        } catch {
            if generation == epoch, !Task.isCancelled, !(error is CancellationError) {
                self.error = "足迹读取失败，可在全部足迹中重试"
            }
        }
    }
    func stop() { generation += 1 }
}
