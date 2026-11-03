#if DEBUG
    import Foundation
    import MallCore

    /// Explicit isolated UI fixtures still exercise the actual persistent store.
    actor FootprintUITestSupport: FootprintStoring {
        nonisolated let scope: FootprintScope
        private let store: any FootprintStoring
        private let prepared: Task<Void, Error>
        private let failure: String?
        private var headReads = 0
        private var appendFailed = false
        init(store: any FootprintStoring, seed: Bool, failure: String?) {
            self.store = store; scope = store.scope; self.failure = failure
            prepared = Task {
                if seed {
                    let current = try await store.page(offset: 0, limit: 1)
                    if current.total == 0 {
                        for id in 1...25 {
                            try await store.record(
                                .init(
                                    id: Int64(830000 + id), title: "足迹夹具商品 \(id)",
                                    subtitle: "本地浏览记录", imageURL: nil, priceYuan: Decimal(id * 100),
                                    sold: Int64(id),
                                    viewedAt: Date(timeIntervalSince1970: Double(id))))
                        }
                    }
                }
            }
        }
        func page(offset: Int, limit: Int) async throws -> FootprintPage {
            try await prepared.value
            if offset == 0 && limit == 20 {
                headReads += 1
                if failure == "refresh" && headReads == 2 { throw FootprintFailure.readFailed }
            }
            if offset > 0 && failure == "append" && !appendFailed {
                appendFailed = true; throw FootprintFailure.readFailed
            }
            return try await store.page(offset: offset, limit: limit)
        }
        func changes() async throws -> AsyncStream<UInt64> {
            try await prepared.value; return try await store.changes()
        }
        func record(_ item: FootprintItem) async throws {
            try await prepared.value; try await store.record(item)
        }
        func clear() async throws { try await prepared.value; try await store.clear() }
    }
#endif
