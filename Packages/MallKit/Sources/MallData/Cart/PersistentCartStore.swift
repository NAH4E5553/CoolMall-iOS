import Foundation
import MallCore
import SwiftData

enum CartSchemaV1: VersionedSchema {
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

enum CartMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CartSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// One explicit actor-isolated context. No ModelContext/@Model escapes this owner.
/// Each scope is a single versioned payload, so a batch is one atomic save.
public actor PersistentCartStore: ShoppingCart {
    private struct Payload: Codable {
        var revision: UInt64 = 0
        var lines: [CartLine] = []
        var additions: Set<UUID> = []
    }
    public nonisolated let scope: CartScope
    private let container: ModelContainer
    private let context: ModelContext
    private var record: CartSchemaV1.Partition?
    private var payload: Payload
    private var subscribers: [UUID: AsyncStream<ShoppingCartSnapshot>.Continuation] = [:]
    private var failNextSave = false

    public init(scope: CartScope, url: URL) throws {
        self.scope = scope
        let schema = Schema(versionedSchema: CartSchemaV1.self)
        let configuration = ModelConfiguration(
            "CartV1", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema, migrationPlan: CartMigrationPlan.self,
            configurations: [configuration])
        self.container = container
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.context = context
        let records = try context.fetch(FetchDescriptor<CartSchemaV1.Partition>()).filter {
            $0.environment == scope.environment && $0.account == scope.accountID
        }
        guard records.count <= 1 else { throw ShoppingCartFailure.readFailed }
        self.record = records.first
        if let record = records.first {
            let decoded = try JSONDecoder().decode(Payload.self, from: record.payload)
            guard Set(decoded.lines.map(\.id)).count == decoded.lines.count,
                decoded.lines.allSatisfy({
                    $0.productID > 0 && $0.specificationID > 0 && $0.quantity > 0
                        && $0.checkedStock >= 0 && $0.unitPrice.cents >= 0
                })
            else { throw ShoppingCartFailure.readFailed }
            self.payload = decoded
        } else {
            self.payload = Payload()
        }
    }

    public func current() throws -> ShoppingCartSnapshot {
        try Task.checkCancellation()
        return snapshot
    }
    public func observe() throws -> AsyncStream<ShoppingCartSnapshot> {
        try Task.checkCancellation()
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: ShoppingCartSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream
    }
    private var snapshot: ShoppingCartSnapshot {
        .init(scope: scope, revision: payload.revision, lines: payload.lines)
    }
    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }

    public func add(
        quantity: Int64, quote: CartQuote, confirmedPrice: CartMoney?, operationID: UUID
    ) throws {
        try Task.checkCancellation()
        if payload.additions.contains(operationID) { return }
        guard quantity > 0 else { throw ShoppingCartFailure.invalidQuantity }
        var next = payload
        let index = next.lines.firstIndex { $0.id == quote.id }
        let previous = index.map { next.lines[$0] }
        let (count, overflow) = (previous?.quantity ?? 0).addingReportingOverflow(quantity)
        guard !overflow else { throw ShoppingCartFailure.invalidQuantity }
        try validate(quote, count: count, old: previous, confirmedPrice: confirmedPrice)
        let line = CartLine(quote: quote, quantity: count)
        if let index { next.lines[index] = line } else { next.lines.append(line) }
        next.additions.insert(operationID)
        try commit(next)
    }
    public func increase(
        _ item: CartItemID, quote: CartQuote, confirmedPrice: CartMoney?, expectedRevision: UInt64
    ) throws {
        try requireRevision(expectedRevision)
        guard quote.id == item, let index = payload.lines.firstIndex(where: { $0.id == item })
        else {
            throw ShoppingCartFailure.missingLine
        }
        let previous = payload.lines[index]
        let (count, overflow) = previous.quantity.addingReportingOverflow(1)
        guard !overflow else { throw ShoppingCartFailure.invalidQuantity }
        try validate(quote, count: count, old: previous, confirmedPrice: confirmedPrice)
        var next = payload; next.lines[index] = .init(quote: quote, quantity: count)
        try commit(next)
    }
    public func decrease(_ item: CartItemID, expectedRevision: UInt64) throws {
        try requireRevision(expectedRevision)
        guard let index = payload.lines.firstIndex(where: { $0.id == item }) else {
            throw ShoppingCartFailure.missingLine
        }
        guard payload.lines[index].quantity > 1 else { throw ShoppingCartFailure.invalidQuantity }
        var next = payload;
        next.lines[index] = next.lines[index].withQuantity(next.lines[index].quantity - 1)
        try commit(next)
    }
    public func remove(_ items: Set<CartItemID>, expectedRevision: UInt64) throws {
        try requireRevision(expectedRevision)
        guard !items.isEmpty, items.isSubset(of: Set(payload.lines.map(\.id))) else {
            throw ShoppingCartFailure.missingLine
        }
        var next = payload; next.lines.removeAll { items.contains($0.id) }
        try commit(next)
    }
    private func requireRevision(_ expected: UInt64) throws {
        try Task.checkCancellation()
        guard expected == payload.revision else { throw ShoppingCartFailure.staleRevision }
    }
    private func validate(
        _ quote: CartQuote, count: Int64, old: CartLine?, confirmedPrice: CartMoney?
    ) throws {
        guard quote.productID > 0, quote.specificationID > 0, quote.stock > 0 else {
            throw ShoppingCartFailure.unavailable
        }
        guard count > 0, count <= quote.stock else {
            throw ShoppingCartFailure.insufficientStock(available: quote.stock)
        }
        if let confirmedPrice, confirmedPrice != quote.price {
            throw ShoppingCartFailure.priceChanged(old: confirmedPrice, new: quote.price)
        }
        if let old, old.unitPrice != quote.price, confirmedPrice != quote.price {
            throw ShoppingCartFailure.priceChanged(old: old.unitPrice, new: quote.price)
        }
        _ = try quote.price.multiplied(by: count)
    }
    private func commit(_ value: Payload) throws {
        try Task.checkCancellation()
        var next = value
        let (revision, overflow) = payload.revision.addingReportingOverflow(1)
        guard !overflow else { throw ShoppingCartFailure.writeFailed }
        next.revision = revision
        // Reject a snapshot whose total count/money cannot be represented.
        let checked = ShoppingCartSnapshot(scope: scope, revision: revision, lines: next.lines)
        _ = try checked.itemCount()
        _ = try checked.total(for: Set(next.lines.map(\.id)))
        do {
            let encoded = try JSONEncoder().encode(next)
            if let record {
                record.payload = encoded
            } else {
                let inserted = CartSchemaV1.Partition(
                    environment: scope.environment, account: scope.accountID, payload: encoded)
                context.insert(inserted); record = inserted
            }
            try Task.checkCancellation()
            if failNextSave { failNextSave = false; throw ShoppingCartFailure.writeFailed }
            try context.save()
        } catch {
            context.rollback()
            record = try? context.fetch(FetchDescriptor<CartSchemaV1.Partition>()).first {
                $0.environment == scope.environment && $0.account == scope.accountID
            }
            if error is CancellationError { throw CancellationError() }
            throw ShoppingCartFailure.writeFailed
        }
        payload = next
        for subscriber in subscribers.values { subscriber.yield(snapshot) }
    }
    // Internal failure injection exercises the actual save/rollback transaction.
    func injectNextSaveFailure() { failNextSave = true }
    deinit { for subscriber in subscribers.values { subscriber.finish() } }
}
