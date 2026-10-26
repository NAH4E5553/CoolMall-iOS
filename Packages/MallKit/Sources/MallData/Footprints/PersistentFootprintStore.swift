import Foundation
import MallCore
import SwiftData

enum FootprintSchemaV1: VersionedSchema {
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
enum FootprintMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FootprintSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
/// App creates one actor per environment/account scope. Only this owner touches its context.
/// Atomic payload commits precede publishing; opening failure never deletes history.
public actor PersistentFootprintStore: FootprintStoring {
    private struct Payload: Codable { var revision: UInt64 = 0; var items: [FootprintItem] = [] }
    public nonisolated let scope: FootprintScope
    private let url: URL
    private var container: ModelContainer?
    private var context: ModelContext?
    private var partition: FootprintSchemaV1.Partition?
    private var payload = Payload()
    private var observers: [UUID: AsyncStream<UInt64>.Continuation] = [:]
    private var failSave = false
    public init(scope: FootprintScope, url: URL) { self.scope = scope; self.url = url }
    private func open() throws {
        guard context == nil else { return }
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: FootprintSchemaV1.self)
            let configuration = ModelConfiguration(
                "FootprintsV1", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(
                for: schema, migrationPlan: FootprintMigrationPlan.self,
                configurations: [configuration])
            let context = ModelContext(container); context.autosaveEnabled = false
            let matches = try context.fetch(FetchDescriptor<FootprintSchemaV1.Partition>()).filter {
                $0.environment == scope.environment && $0.account == scope.accountID
            }
            guard matches.count <= 1 else { throw FootprintFailure.readFailed }
            let value =
                try matches.first.map { try JSONDecoder().decode(Payload.self, from: $0.payload) }
                ?? Payload()
            guard Set(value.items.map(\.id)).count == value.items.count,
                value.items.allSatisfy(Self.valid)
            else { throw FootprintFailure.readFailed }
            self.container = container; self.context = context; partition = matches.first;
            payload = value
        } catch is CancellationError { throw CancellationError() } catch {
            throw FootprintFailure.readFailed
        }
    }
    private static func valid(_ item: FootprintItem) -> Bool {
        item.id > 0 && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !item.priceYuan.isNaN && item.priceYuan >= 0 && item.sold >= 0
            && item.viewedAt.timeIntervalSince1970.isFinite
    }
    public func page(offset: Int, limit: Int) throws -> FootprintPage {
        try Task.checkCancellation(); try open()
        guard offset >= 0, (1...100).contains(limit) else { throw FootprintFailure.invalidPage }
        let all = payload.items.sorted {
            $0.viewedAt == $1.viewedAt ? $0.id > $1.id : $0.viewedAt > $1.viewedAt
        }
        let start = min(offset, all.count); let end = start + min(limit, all.count - start)
        return .init(
            items: Array(all[start..<end]), total: all.count, revision: payload.revision,
            nextOffset: end < all.count ? end : nil)
    }
    public func changes() throws -> AsyncStream<UInt64> {
        try Task.checkCancellation(); try open()
        let id = UUID();
        let (stream, continuation) = AsyncStream<UInt64>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation; continuation.yield(payload.revision)
        continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        return stream
    }
    private func remove(_ id: UUID) { observers[id] = nil }
    public func record(_ item: FootprintItem) throws {
        try Task.checkCancellation(); try open();
        guard Self.valid(item) else { throw FootprintFailure.invalidRecord }
        var next = payload; next.items.removeAll { $0.id == item.id }; next.items.append(item);
        try commit(next)
    }
    public func clear() throws {
        try Task.checkCancellation(); try open(); var next = payload; next.items = [];
        try commit(next)
    }
    private func commit(_ proposed: Payload) throws {
        guard let context else { throw FootprintFailure.writeFailed }
        var next = proposed; next.revision &+= 1
        do {
            let data = try JSONEncoder().encode(next)
            if let partition {
                partition.payload = data
            } else {
                let row = FootprintSchemaV1.Partition(
                    environment: scope.environment, account: scope.accountID, payload: data);
                context.insert(row); partition = row
            }
            try Task.checkCancellation()
            if failSave { failSave = false; throw FootprintFailure.writeFailed }
            try context.save()
        } catch {
            context.rollback()
            partition = try? context.fetch(FetchDescriptor<FootprintSchemaV1.Partition>()).first {
                $0.environment == scope.environment && $0.account == scope.accountID
            }
            if error is CancellationError { throw CancellationError() };
            throw FootprintFailure.writeFailed
        }
        payload = next; for observer in observers.values { observer.yield(next.revision) }
    }
    deinit { for observer in observers.values { observer.finish() } }
    func failNextCommitForTesting() { failSave = true }
}
