import Foundation
import MallCore
import SwiftData

enum SearchHistorySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Partition.self] }
    @Model final class Partition {
        var environment: String
        var account: String?
        var payload: Data
        init(environment: String, account: String?, payload: Data) {
            self.environment = environment; self.account = account; self.payload = payload
        }
    }
}
enum SearchHistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SearchHistorySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
/// App creates one actor per environment/account scope. Only this owner touches its context.
/// Atomic payload commits precede publishing; opening failure never deletes history.
public actor PersistentSearchHistoryStore: SearchHistoryStoring {
    private struct Payload: Codable { var revision: UInt64 = 0; var keywords: [String] = [] }
    public nonisolated let scope: SearchHistoryScope
    private let url: URL
    private var container: ModelContainer?
    private var context: ModelContext?
    private var partition: SearchHistorySchemaV1.Partition?
    private var payload = Payload()
    private var observers: [UUID: AsyncStream<SearchHistorySnapshot>.Continuation] = [:]
    private var failSave = false
    public init(scope: SearchHistoryScope, url: URL) { self.scope = scope; self.url = url }
    private func open() throws {
        guard context == nil else { return }
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: SearchHistorySchemaV1.self)
            let configuration = ModelConfiguration(
                "SearchHistoryV1", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(
                for: schema, migrationPlan: SearchHistoryMigrationPlan.self,
                configurations: [configuration])
            let context = ModelContext(container); context.autosaveEnabled = false
            let matches = try context.fetch(FetchDescriptor<SearchHistorySchemaV1.Partition>())
                .filter {
                    $0.environment == scope.environment && $0.account == scope.accountID
                }
            guard matches.count <= 1 else { throw SearchHistoryFailure.readFailed }
            let value =
                try matches.first.map { try JSONDecoder().decode(Payload.self, from: $0.payload) }
                ?? Payload()
            guard value.keywords.count <= 10, Set(value.keywords).count == value.keywords.count,
                value.keywords.allSatisfy({
                    !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
                })
            else { throw SearchHistoryFailure.readFailed }
            self.container = container; self.context = context; partition = matches.first;
            payload = value
        } catch is CancellationError { throw CancellationError() } catch {
            throw SearchHistoryFailure.readFailed
        }
    }
    func snapshot() throws -> SearchHistorySnapshot {
        try Task.checkCancellation(); try open()
        return SearchHistorySnapshot(keywords: payload.keywords, revision: payload.revision)
    }
    public func changes() throws -> AsyncStream<SearchHistorySnapshot> {
        try Task.checkCancellation(); try open()
        let id = UUID()
        let (stream, continuation) = AsyncStream<SearchHistorySnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.yield(
            SearchHistorySnapshot(keywords: payload.keywords, revision: payload.revision))
        continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        return stream
    }
    private func remove(_ id: UUID) { observers[id] = nil }
    public func record(_ keyword: String) throws {
        try Task.checkCancellation()
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        try open()
        var next = payload
        next.keywords.removeAll { $0 == word }
        next.keywords.insert(word, at: 0)
        next.keywords = Array(next.keywords.prefix(10))
        try commit(next)
    }
    public func clear() throws {
        try Task.checkCancellation(); try open()
        var next = payload; next.keywords = []; try commit(next)
    }
    private func commit(_ proposed: Payload) throws {
        guard let context else { throw SearchHistoryFailure.writeFailed }
        var next = proposed; next.revision &+= 1
        do {
            let data = try JSONEncoder().encode(next)
            if let partition {
                partition.payload = data
            } else {
                let row = SearchHistorySchemaV1.Partition(
                    environment: scope.environment, account: scope.accountID, payload: data);
                context.insert(row); partition = row
            }
            try Task.checkCancellation()
            if failSave { failSave = false; throw SearchHistoryFailure.writeFailed }
            try context.save()
        } catch {
            context.rollback()
            partition = try? context.fetch(FetchDescriptor<SearchHistorySchemaV1.Partition>()).first
            {
                $0.environment == scope.environment && $0.account == scope.accountID
            }
            if error is CancellationError { throw CancellationError() };
            throw SearchHistoryFailure.writeFailed
        }
        payload = next;
        for observer in observers.values {
            observer.yield(SearchHistorySnapshot(keywords: next.keywords, revision: next.revision))
        }
    }
    deinit { for observer in observers.values { observer.finish() } }
    func failNextCommitForTesting() { failSave = true }
}
