import Foundation
import MallCore
import Testing
@testable import MallData

struct PersistentSearchHistoryStoreTests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(
            path: "search.store")
    }
    private func store(_ url: URL, _ account: String? = nil, environment: String = "test")
        -> PersistentSearchHistoryStore
    {
        PersistentSearchHistoryStore(
            scope: .init(environment: environment, accountID: account), url: url)
    }
    @Test func diskReopenKeepsTrimmedDistinctTenInCommittedOrder() async throws {
        let url = url();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let owner = store(url)
        for n in 1...11 { try await owner.record("词\(n)") }
        try await owner.record(" 词5 \n")
        try await owner.record(" \n ")
        let restored = try await store(url).snapshot()
        #expect(
            restored.keywords == ["词5", "词11", "词10", "词9", "词8", "词7", "词6", "词4", "词3", "词2"])
        #expect(restored.revision == 12)
    }
    @Test func scopesGuestAccountsEnvironmentAndClearRemainSeparate() async throws {
        let url = url();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try await store(url).record("游客"); try await store(url, "a").record("账号A")
        try await store(url, "b").record("账号B");
        try await store(url, "a", environment: "other").record("环境")
        try await store(url, "a").clear()
        #expect(try await store(url).snapshot().keywords == ["游客"])
        #expect(try await store(url, "a").snapshot().keywords == [])
        #expect(try await store(url, "b").snapshot().keywords == ["账号B"])
        #expect(try await store(url, "a", environment: "other").snapshot().keywords == ["环境"])
    }
    @Test func saveAndClearFailureNeverPublishOrCorruptCommittedData() async throws {
        let url = url();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let owner = store(url); try await owner.record("已保存")
        let before = try await owner.snapshot()
        await owner.failNextCommitForTesting()
        await #expect(throws: SearchHistoryFailure.writeFailed) { try await owner.record("失败") }
        #expect(try await owner.snapshot() == before)
        await owner.failNextCommitForTesting()
        await #expect(throws: SearchHistoryFailure.writeFailed) { try await owner.clear() }
        #expect(try await store(url).snapshot() == before)
    }
    @Test func firstSaveFailureCanRecoverAndReleasedStoreReallyReopens() async throws {
        let url = url();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let owner = store(url); await owner.failNextCommitForTesting()
            await #expect(throws: SearchHistoryFailure.writeFailed) {
                try await owner.record("失败首条")
            }
            #expect(try await owner.snapshot().keywords.isEmpty)
            try await owner.record("恢复成功")
        }
        #expect(try await store(url).snapshot().keywords == ["恢复成功"])
    }
    @Test func concurrentRecordAndClearAreAtomicAndNewSearchAfterClearWins() async throws {
        let url = url();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let owner = store(url)
        async let record: Void = owner.record("并发词")
        async let clear: Void = owner.clear()
        _ = try await (record, clear)
        #expect(try await owner.snapshot().revision == 2)
        try await owner.clear(); try await owner.record("明确新搜索")
        #expect(try await store(url).snapshot().keywords == ["明确新搜索"])
    }
    @Test func streamStartsWithSnapshotAndOnlyCommittedChangesClearSurvivesReopen() async throws {
        let url = url();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let owner = store(url); try await owner.record("旧词")
        var iterator = try await owner.changes().makeAsyncIterator()
        #expect(await iterator.next()?.keywords == ["旧词"])
        try await owner.clear(); #expect(await iterator.next()?.keywords == [])
        try await owner.record("新词"); #expect(await iterator.next()?.keywords == ["新词"])
        #expect(try await store(url).snapshot().keywords == ["新词"])
    }
    @Test func cancelledWriteDoesNotPublishAndCorruptFileIsNotDeleted() async throws {
        let url = url();
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let owner = store(url)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }; try await owner.record("取消")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await owner.snapshot().keywords.isEmpty)
        let badURL = url.deletingLastPathComponent().appending(path: "bad.store")
        let bytes = Data("not a database".utf8); try bytes.write(to: badURL)
        await #expect(throws: SearchHistoryFailure.readFailed) {
            try await store(badURL).snapshot()
        }
        #expect(try Data(contentsOf: badURL) == bytes)
    }
}
