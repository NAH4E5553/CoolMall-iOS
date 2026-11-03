#if DEBUG
    import Foundation
    import MallCore
    import MallData

    struct CartUITestSupport {
        static func make(loader: any ProductDetailLoading, directory: URL, accountID: String?) -> (
            any ShoppingCart
        )? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--ui-cart-store"),
                arguments.indices.contains(index + 1),
                let token = UUID(uuidString: arguments[index + 1])
            else { return nil }
            let store = LocalShoppingCart(
                scope: .init(environment: "cart-ui-fixture", accountID: accountID),
                url: directory.appending(path: "test-\(token.uuidString).store"))
            return PreparedCart(
                store: store, loader: loader, seed: arguments.contains("--ui-cart-seed"))
        }
    }

    private struct PreparedCart: ShoppingCart {
        var scope: CartScope { store.scope }
        let store: any ShoppingCart
        let ready: Task<Void, Error>
        init(store: any ShoppingCart, loader: any ProductDetailLoading, seed: Bool) {
            self.store = store
            ready = Task {
                guard seed, try await store.current().lines.isEmpty else { return }
                let check = try await CartProductVerifier(loader: loader).check(productID: 830001)
                for quote in check.quotes.filter({ $0.stock > 0 }).prefix(2) {
                    try await store.add(
                        quantity: 1, quote: quote, confirmedPrice: nil, operationID: UUID())
                }
            }
        }
        func observe() async throws -> AsyncStream<ShoppingCartSnapshot> {
            try await ready.value; return try await store.observe()
        }
        func current() async throws -> ShoppingCartSnapshot {
            try await ready.value; return try await store.current()
        }
        func add(quantity: Int64, quote: CartQuote, confirmedPrice: CartMoney?, operationID: UUID)
            async throws
        {
            try await ready.value
            try await store.add(
                quantity: quantity, quote: quote, confirmedPrice: confirmedPrice,
                operationID: operationID)
        }
        func increase(
            _ item: CartItemID, quote: CartQuote, confirmedPrice: CartMoney?,
            expectedRevision: UInt64
        ) async throws {
            try await ready.value
            try await store.increase(
                item, quote: quote, confirmedPrice: confirmedPrice,
                expectedRevision: expectedRevision)
        }
        func decrease(_ item: CartItemID, expectedRevision: UInt64) async throws {
            try await ready.value;
            try await store.decrease(item, expectedRevision: expectedRevision)
        }
        func remove(_ items: Set<CartItemID>, expectedRevision: UInt64) async throws {
            try await ready.value; try await store.remove(items, expectedRevision: expectedRevision)
        }
    }
#endif
