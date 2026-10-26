import Foundation
import MallCore
import Testing
@testable import MallData

struct PersistentFootprintStoreTests {
    private func item(_ id: Int64, time: Double = 1, title: String = "商品") -> FootprintItem {
        .init(
            id: id, title: title, subtitle: "副标题", imageURL: nil,
            priceYuan: Decimal(string: "12.34") ?? 0, sold: 2,
            viewedAt: Date(timeIntervalSince1970: time))
    }
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(
            path: "history.store")
    }
    private func store(_ url: URL, account: String? = nil, environment: String = "test")
        -> PersistentFootprintStore
    { .init(scope: .init(environment: environment, accountID: account), url: url) }
    @Test func persistsDeduplicatesAndRestoresNewestSummary() async throws {
        let url = location();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let owner = store(url)
        try await owner.record(item(1)); try await owner.record(item(2, time: 2));
        try await owner.record(item(1, time: 3, title: "更新商品"))
        let restored = store(url); let page = try await restored.page(offset: 0, limit: 8)
        #expect(page.items.map(\.id) == [1, 2]); #expect(page.items.first?.title == "更新商品");
        #expect(page.total == 2); #expect(page.revision == 3)
    }
    @Test func localPagesHaveStableOrderAndExplicitEnd() async throws {
        let url = location();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) };
        let owner = store(url)
        for id in 1...25 { try await owner.record(item(Int64(id), time: Double(id))) }
        let head = try await owner.page(offset: 0, limit: 20);
        let tail = try await owner.page(offset: 20, limit: 20)
        #expect(head.items.map(\.id) == Array((6...25).reversed()).map(Int64.init));
        #expect(head.nextOffset == 20)
        #expect(tail.items.map(\.id) == [5, 4, 3, 2, 1]); #expect(tail.nextOffset == nil);
        #expect(tail.revision == head.revision)
        let preview = try await owner.page(offset: 0, limit: 8); #expect(preview.items.count == 8);
        #expect(preview.total == 25)
        try await owner.clear()
        let reopened = store(url)
        #expect(try await reopened.page(offset: 0, limit: 8).total == 0)
    }
    @Test func guestAccountsAndEnvironmentRemainIsolatedAfterScopedClear() async throws {
        let url = location();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let guest = store(url); let a = store(url, account: "a"); let b = store(url, account: "b");
        let other = store(url, environment: "other")
        try await guest.record(item(1)); try await a.record(item(2)); try await b.record(item(3));
        try await other.record(item(4)); try await a.clear()
        #expect(try await store(url).page(offset: 0, limit: 8).items.map(\.id) == [1])
        #expect(try await store(url, account: "a").page(offset: 0, limit: 8).total == 0)
        #expect(try await store(url, account: "b").page(offset: 0, limit: 8).items.map(\.id) == [3])
        #expect(
            try await store(url, environment: "other").page(offset: 0, limit: 8).items.map(\.id)
                == [4])
    }
    @Test func failedSaveAndClearRollBackWithoutPublishingNewRevision() async throws {
        let url = location();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) };
        let owner = store(url)
        try await owner.record(item(1)); let before = try await owner.page(offset: 0, limit: 8)
        await owner.failNextCommitForTesting()
        await #expect(throws: FootprintFailure.writeFailed) { try await owner.record(item(2)) }
        #expect(try await owner.page(offset: 0, limit: 8) == before)
        await owner.failNextCommitForTesting();
        await #expect(throws: FootprintFailure.writeFailed) { try await owner.clear() }
        #expect(try await store(url).page(offset: 0, limit: 8) == before)
    }
    @Test func invalidInputAndCancelledMutationCannotAddHistory() async throws {
        let url = location();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) };
        let owner = store(url)
        await #expect(throws: FootprintFailure.invalidRecord) { try await owner.record(item(0)) }
        await #expect(throws: FootprintFailure.invalidPage) {
            try await owner.page(offset: -1, limit: 20)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }; try await owner.record(item(1))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await owner.page(offset: 0, limit: 8).total == 0)
    }
    @Test func observesOnlyCommittedRevisionsAndClearPersists() async throws {
        let url = location();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) };
        let owner = store(url)
        var iterator = try await owner.changes().makeAsyncIterator();
        #expect(await iterator.next() == 0)
        try await owner.record(item(1)); #expect(await iterator.next() == 1)
        try await owner.clear(); #expect(await iterator.next() == 2)
        #expect(try await store(url).page(offset: 0, limit: 8).total == 0)
    }
}
