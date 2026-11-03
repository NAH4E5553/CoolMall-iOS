import Foundation
import MallCore
@testable import MallData
import Testing

@Suite struct ShoppingCartStoreTests {
    private let scope = CartScope(environment: "production", accountID: nil)
    private func url() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(
            path: "cart-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "cart.store")
    }
    private func quote(_ spec: Int64 = 1, price: Decimal = 100, stock: Int64 = 10) throws
        -> CartQuote
    {
        .init(
            productID: 1, specificationID: spec, title: "手机", specification: "规格\(spec)",
            imageURL: nil,
            price: try CartMoney(yuan: price), stock: stock)
    }
    @Test func actualDiskReopenRetainsMetadataRevisionAndDedupe() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let operation = UUID()
        do {
            let store = try PersistentCartStore(scope: scope, url: path)
            try await store.add(
                quantity: 2, quote: quote(), confirmedPrice: nil, operationID: operation)
            try await store.add(
                quantity: 1, quote: quote(2), confirmedPrice: nil, operationID: UUID())
        }
        let reopened = try PersistentCartStore(scope: scope, url: path)
        try await reopened.add(
            quantity: 2, quote: quote(), confirmedPrice: nil, operationID: operation)
        let value = try await reopened.current()
        #expect(value.revision == 2)
        #expect(value.lines.map(\.specificationID) == [1, 2])
        #expect(value.lines.first?.quantity == 2)
        #expect(value.lines.first?.title == "手机")
        #expect(try value.itemCount() == 3)
    }
    @Test func concurrentAddsRecheckLatestQuantityAndNeverExceedStock() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = try PersistentCartStore(scope: scope, url: path)
        let checked = try quote(stock: 7)
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do {
                        try await store.add(
                            quantity: 1, quote: checked, confirmedPrice: nil, operationID: UUID());
                        return true
                    } catch let error as ShoppingCartFailure {
                        #expect(error == .insufficientStock(available: 7)); return false
                    } catch {
                        Issue.record("Unexpected concurrent-add failure: \(error)"); return false
                    }
                }
            }
            var accepted = 0
            for await success in group { if success { accepted += 1 } }
            return accepted
        }
        #expect(results == 7)
        let value = try await store.current()
        #expect(value.lines.first?.quantity == 7)
        #expect(value.revision == 7)
    }
    @Test func changedPriceRequiresExactAuthorizationForWholeLine() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = try PersistentCartStore(scope: scope, url: path)
        try await store.add(quantity: 2, quote: quote(), confirmedPrice: nil, operationID: UUID())
        let old = try await store.current()
        await #expect(
            throws: ShoppingCartFailure.priceChanged(
                old: try CartMoney(yuan: 100), new: try CartMoney(yuan: 120))
        ) {
            try await store.add(
                quantity: 1, quote: quote(price: 120), confirmedPrice: nil, operationID: UUID())
        }
        #expect(try await store.current() == old)
        try await store.add(
            quantity: 1, quote: quote(price: 120), confirmedPrice: CartMoney(yuan: 120),
            operationID: UUID())
        let value = try await store.current()
        #expect(value.lines.first?.quantity == 3)
        #expect(try value.total(for: [quote().id]).cents == 36000)
        await #expect(
            throws: ShoppingCartFailure.priceChanged(
                old: try CartMoney(yuan: 120), new: try CartMoney(yuan: 130))
        ) {
            try await store.add(
                quantity: 1, quote: quote(price: 130), confirmedPrice: CartMoney(yuan: 120),
                operationID: UUID())
        }
    }
    @Test func explicitPriceAuthorizationMustMatchEvenWhenQuoteReturnsToStoredPrice() async throws {
        for adding in [true, false] {
            let path = try url();
            defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
            let store = try PersistentCartStore(scope: scope, url: path)
            let original = try quote()
            try await store.add(
                quantity: 2, quote: original, confirmedPrice: nil, operationID: UUID())
            let before = try await store.current()
            await #expect(
                throws: ShoppingCartFailure.priceChanged(
                    old: try CartMoney(yuan: 120), new: original.price)
            ) {
                if adding {
                    try await store.add(
                        quantity: 1, quote: original, confirmedPrice: CartMoney(yuan: 120),
                        operationID: UUID())
                } else {
                    try await store.increase(
                        original.id, quote: original, confirmedPrice: CartMoney(yuan: 120),
                        expectedRevision: before.revision)
                }
            }
            #expect(try await store.current() == before)
        }
    }
    @Test func saveFailureRollsBackAddAndEntireBatchAndRevision() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = try PersistentCartStore(scope: scope, url: path)
        await store.injectNextSaveFailure()
        await #expect(throws: ShoppingCartFailure.writeFailed) {
            try await store.add(
                quantity: 1, quote: quote(), confirmedPrice: nil, operationID: UUID())
        }
        #expect(try await store.current().lines.isEmpty)
        try await store.add(quantity: 1, quote: quote(), confirmedPrice: nil, operationID: UUID())
        try await store.add(quantity: 1, quote: quote(2), confirmedPrice: nil, operationID: UUID())
        let old = try await store.current()
        await store.injectNextSaveFailure()
        await #expect(throws: ShoppingCartFailure.writeFailed) {
            try await store.remove(Set(old.lines.map(\.id)), expectedRevision: old.revision)
        }
        #expect(try await store.current() == old)
        let reopened = try PersistentCartStore(scope: scope, url: path)
        #expect(try await reopened.current() == old)
        try await store.remove(Set(old.lines.map(\.id)), expectedRevision: old.revision)
        #expect(try await store.current().lines.isEmpty)
    }
    @Test func staleRevisionCannotOverwriteOtherHostAndDecreaseKeepsPrice() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = try PersistentCartStore(scope: scope, url: path)
        let q = try quote()
        try await store.add(quantity: 2, quote: q, confirmedPrice: nil, operationID: UUID())
        let revision = try await store.current().revision
        try await store.increase(q.id, quote: q, confirmedPrice: nil, expectedRevision: revision)
        await #expect(throws: ShoppingCartFailure.staleRevision) {
            try await store.decrease(q.id, expectedRevision: revision)
        }
        let current = try await store.current()
        try await store.decrease(q.id, expectedRevision: current.revision)
        #expect(try await store.current().lines.first?.quantity == 2)
        #expect(try await store.current().lines.first?.unitPrice == q.price)
    }
    @Test func guestAccountsAndEnvironmentsAreDiskIsolated() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let scopes = [
            scope, CartScope(environment: "production", accountID: "A"),
            CartScope(environment: "production", accountID: "B"),
            CartScope(environment: "staging", accountID: "A"),
        ]
        for (index, value) in scopes.enumerated() {
            let store = try PersistentCartStore(scope: value, url: path)
            #expect(try await store.current().lines.isEmpty)
            try await store.add(
                quantity: Int64(index + 1), quote: quote(), confirmedPrice: nil, operationID: UUID()
            )
        }
        for (index, value) in scopes.enumerated() {
            let store = try PersistentCartStore(scope: value, url: path)
            #expect(try await store.current().lines.first?.quantity == Int64(index + 1))
        }
    }
    @Test func cancellationBeforeCommitNeverPublishesAndSubscribersSeeSameRevision() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = try PersistentCartStore(scope: scope, url: path)
        var a = try await store.observe().makeAsyncIterator()
        var b = try await store.observe().makeAsyncIterator()
        #expect(await a.next()?.revision == 0)
        #expect(await b.next()?.revision == 0)
        let checked = try quote()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.add(
                quantity: 1, quote: checked, confirmedPrice: nil, operationID: UUID())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await store.current().revision == 0)
        try await store.add(quantity: 1, quote: checked, confirmedPrice: nil, operationID: UUID())
        #expect(await a.next() == b.next())
    }
    @Test func insufficientStockAndZeroQuantityLeaveCartUnchanged() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let store = try PersistentCartStore(scope: scope, url: path)
        try await store.add(
            quantity: 3, quote: quote(stock: 5), confirmedPrice: nil, operationID: UUID())
        let old = try await store.current()
        await #expect(throws: ShoppingCartFailure.insufficientStock(available: 5)) {
            try await store.add(
                quantity: 3, quote: quote(stock: 5), confirmedPrice: nil, operationID: UUID())
        }
        await #expect(throws: ShoppingCartFailure.invalidQuantity) {
            try await store.add(
                quantity: 0, quote: quote(), confirmedPrice: nil, operationID: UUID())
        }
        #expect(try await store.current() == old)
    }
    @Test func lazyOpenFailureIsRecoverableWithoutMemoryFallback() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let blocked = path.deletingLastPathComponent().appending(path: "blocked")
        try Data("file-not-directory".utf8).write(to: blocked)
        let store = LocalShoppingCart(scope: scope, url: blocked.appending(path: "cart.store"))
        await #expect(throws: (any Error).self) { try await store.current() }
        try FileManager.default.removeItem(at: blocked)
        try await store.add(quantity: 1, quote: quote(), confirmedPrice: nil, operationID: UUID())
        #expect(try await store.current().lines.count == 1)
        let reopen = try PersistentCartStore(
            scope: scope, url: blocked.appending(path: "cart.store"))
        #expect(try await reopen.current().lines.count == 1)
    }
    @Test func invalidDiskIsNotSilentlyReplacedWithEmptyCart() async throws {
        let path = try url();
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let bytes = Data("this-is-not-a-database".utf8)
        try bytes.write(to: path)
        #expect(throws: (any Error).self) { try PersistentCartStore(scope: scope, url: path) }
        #expect(try Data(contentsOf: path) == bytes)
    }
}
