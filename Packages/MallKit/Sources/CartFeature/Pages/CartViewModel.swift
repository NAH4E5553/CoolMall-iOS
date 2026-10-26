import Foundation
import MallCore
import Observation

/// Page owns drafts/tasks only. The injected store owns all committed rows.
@MainActor @Observable
final class CartViewModel {
    enum Status { case loading, ready, failed }
    private static let pendingMessage = "当前购物项正在处理，请稍后再操作"
    enum WriteOperation: Equatable { case quantity(CartItemID), removal, checkout }
    struct PriceConfirmation {
        let item: CartItemID
        let old: CartMoney
        let new: CartMoney
        let quantity: Int64
        let revision: UInt64
        var text: String {
            "单价由\(old.formatted)变为\(new.formatted)，新价将用于该规格全部\(quantity)件，调整后该行合计\((try? new.multiplied(by: quantity).formatted) ?? "金额异常")。确认后会再次核验价格和库存。"
        }
    }
    private let store: any ShoppingCart
    private let verifier: any CartProductChecking
    private(set) var snapshot: ShoppingCartSnapshot?
    private(set) var status: Status = .loading
    private(set) var selection: Set<CartItemID> = []
    private(set) var editing = false
    private(set) var operation: WriteOperation?
    var busy: Bool { operation != nil }
    var processingItem: CartItemID? {
        if case .quantity(let item) = operation { return item }
        return nil
    }
    var isRemoving: Bool { operation == .removal }
    var checkingOut: Bool { operation == .checkout }
    private(set) var message: String?
    private(set) var confirmation: PriceConfirmation?
    private(set) var checks: [Int64: CartProductCheck] = [:]
    private(set) var checkFailures: Set<Int64> = []
    private var mutation: Task<Void, Never>?
    private var verification: Task<Void, Never>?
    private var active = false
    private var generation = 0
    init(store: any ShoppingCart, verifier: any CartProductChecking) {
        self.store = store; self.verifier = verifier
    }
    var groups: [Int64] {
        var seen: Set<Int64> = []
        return (snapshot?.lines ?? []).compactMap {
            seen.insert($0.productID).inserted ? $0.productID : nil
        }
    }
    func lines(for product: Int64) -> [CartLine] {
        snapshot?.lines.filter { $0.productID == product } ?? []
    }
    func eligible(_ line: CartLine) -> Bool {
        guard let check = checks[line.productID], let quote = try? check.quote(for: line.id) else {
            return false
        }
        return line.quantity <= quote.stock
    }
    var selectable: Set<CartItemID> {
        Set((snapshot?.lines ?? []).filter { editing || eligible($0) }.map(\.id))
    }
    var allSelected: Bool { !selectable.isEmpty && selection == selectable }
    var total: CartMoney? { try? snapshot?.total(for: selection) }
    func toggle(_ item: CartItemID) {
        guard !checkingOut, selectable.contains(item) else { return }
        if !selection.insert(item).inserted { selection.remove(item) }
    }
    func toggleAll() {
        guard !checkingOut else { return }; selection = allSelected ? [] : selectable
    }
    func toggleEditing() {
        guard !isRemoving, !checkingOut, confirmation == nil else { return }
        editing.toggle(); selection = []
    }
    func note(for line: CartLine) -> String? {
        guard let check = checks[line.productID] else {
            // Revalidation must not insert and then remove a line on every entry.
            // Unknown facts still block selection until the real check completes.
            return checkFailures.contains(line.productID) ? "未核验，点击重试" : nil
        }
        guard let quote = try? check.quote(for: line.id) else { return "商品或规格失效／暂无库存" }
        if line.quantity > quote.stock { return "库存不足，当前可售\(quote.stock)件，请减量或删除" }
        if line.unitPrice != quote.price { return "现价\(quote.price.formatted)，增加数量前需确认" }
        return nil
    }
    func observe() async {
        stop()
        active = true; status = snapshot == nil ? .loading : .ready
        let token = generation
        do {
            let stream = try await store.observe()
            for await value in stream {
                guard active, generation == token, !Task.isCancelled else { return }
                guard value.scope == store.scope else { continue }
                if let current = snapshot {
                    guard value.scope == current.scope, value.revision >= current.revision else {
                        continue
                    }
                }
                snapshot = value; status = .ready
                selection.formIntersection(selectable)
                verifyMissing()
            }
        } catch {
            guard active, generation == token, !Task.isCancelled else { return }
            status = .failed; message = "购物车读取失败，原数据未清除，请重试"
        }
    }
    func stop() {
        active = false; generation += 1
        mutation?.cancel(); mutation = nil; verification?.cancel(); verification = nil
        endOperation(); confirmation = nil; selection = []; checks = [:]; checkFailures = []
    }
    func retryChecks() {
        guard active, !busy, confirmation == nil else { return }
        verification?.cancel(); verification = nil
        checks = [:]; checkFailures = []
        if !editing { selection = [] }
        verifyMissing()
    }
    func canIncrease(_ line: CartLine) -> Bool {
        guard let check = checks[line.productID] else { return true }
        guard let quote = try? check.quote(for: line.id) else { return false }
        return line.quantity < quote.stock
    }
    private func verifyMissing() {
        guard verification == nil else { return }
        let products = groups.filter { checks[$0] == nil && !checkFailures.contains($0) }
        guard !products.isEmpty else { return }
        let token = generation
        verification = Task { [weak self, verifier] in
            for id in products {
                do {
                    let check = try await verifier.check(productID: id)
                    try Task.checkCancellation()
                    guard let self, self.active, self.generation == token else { return }
                    guard check.productID == id else { throw ShoppingCartFailure.unavailable }
                    self.checks[id] = check
                    if !self.editing { self.selection.formIntersection(self.selectable) }
                } catch {
                    guard let self, self.active, self.generation == token, !Task.isCancelled else {
                        return
                    }
                    self.checkFailures.insert(id)
                }
            }
            guard let self, self.active, self.generation == token, !Task.isCancelled else { return }
            self.verification = nil
            self.verifyMissing()
        }
    }
    func checkout(onReady: @escaping @MainActor (CheckoutIntent) -> Void) {
        guard !editing, confirmation == nil, !selection.isEmpty,
            canStart(.checkout), let value = snapshot
        else { return }
        let chosen = selection
        guard chosen.isSubset(of: selectable) else { return }
        operation = .checkout; message = nil
        verification?.cancel(); verification = nil
        let token = generation
        mutation = Task { [weak self, store, verifier] in
            do {
                var fresh: [Int64: CartProductCheck] = [:]
                for line in value.lines where chosen.contains(line.id) {
                    if fresh[line.productID] != nil { continue }
                    let check = try await verifier.check(productID: line.productID)
                    try Task.checkCancellation()
                    guard let self, self.active, self.generation == token else { return }
                    guard check.productID == line.productID else {
                        throw ShoppingCartFailure.unavailable
                    }
                    fresh[line.productID] = check; self.checks[line.productID] = check
                }
                let current = try await store.current()
                try Task.checkCancellation()
                guard let self, self.active, self.generation == token else { return }
                guard current.scope == value.scope, current.revision == value.revision,
                    self.selection == chosen
                else { throw ShoppingCartFailure.staleRevision }
                let intent = try CheckoutIntent(cart: current, selection: chosen, checks: fresh)
                self.finish(token); onReady(intent)
            } catch { self?.finish(token, error: error) }
        }
    }
    func decrease(_ item: CartItemID) {
        guard let revision = snapshot?.revision else { return }
        run(.quantity(item)) { [store] in try await store.decrease(item, expectedRevision: revision)
        }
    }
    func removeSelected() {
        guard let revision = snapshot?.revision, !selection.isEmpty else { return }
        let items = selection
        run(.removal, exitEditing: true) { [store] in
            try await store.remove(items, expectedRevision: revision)
        }
    }
    func increase(_ item: CartItemID, acceptedPrice: CartMoney? = nil, expected: UInt64? = nil) {
        guard canStart(.quantity(item)), let value = snapshot,
            let line = value.lines.first(where: { $0.id == item })
        else { return }
        if let expected, expected != value.revision {
            message = "购物车已变化，请重新操作"; confirmation = nil; return
        }
        confirmation = nil; operation = .quantity(item); message = nil
        // This explicit read supersedes any older entry verification. A late
        // response from that cancelled read must not restore stale eligibility.
        verification?.cancel(); verification = nil
        let token = generation
        mutation = Task { [weak self, store, verifier] in
            var receivedCheck = false
            do {
                let check = try await verifier.check(productID: item.productID)
                try Task.checkCancellation()
                guard let self, self.active, self.generation == token else { return }
                guard check.productID == item.productID else {
                    throw ProductDetailLoadFailure.invalidResponse
                }
                // Apply the whole product fact before quote/quantity validation
                // can fail, and remove all newly ineligible SKU selections.
                self.checks[item.productID] = check
                self.checkFailures.remove(item.productID); receivedCheck = true
                if !self.editing { self.selection.formIntersection(self.selectable) }
                self.verifyMissing()
                let quote = try check.quote(for: item)
                let (quantity, overflow) = line.quantity.addingReportingOverflow(1)
                guard !overflow else { throw ShoppingCartFailure.invalidQuantity }
                guard quantity <= quote.stock else {
                    throw ShoppingCartFailure.insufficientStock(available: quote.stock)
                }
                _ = try quote.price.multiplied(by: quantity)
                let needsConfirmation =
                    acceptedPrice.map { $0 != quote.price } ?? (line.unitPrice != quote.price)
                if needsConfirmation {
                    self.confirmation = .init(
                        item: item, old: acceptedPrice ?? line.unitPrice, new: quote.price,
                        quantity: quantity, revision: value.revision)
                    self.endOperation(); return
                }
                try await store.increase(
                    item, quote: quote, confirmedPrice: acceptedPrice,
                    expectedRevision: value.revision)
                self.finish(token)
            } catch {
                if !receivedCheck, let self, self.active, self.generation == token,
                    !Task.isCancelled, !(error is CancellationError)
                {
                    // No new product fact: mark unknown/retryable, never sold out.
                    self.checks.removeValue(forKey: item.productID)
                    self.checkFailures.insert(item.productID)
                    if !self.editing { self.selection.formIntersection(self.selectable) }
                }
                self?.finish(token, error: error)
            }
        }
    }
    func confirmPrice() {
        guard let value = confirmation else { return }
        increase(value.item, acceptedPrice: value.new, expected: value.revision)
    }
    func cancelPrice() { confirmation = nil }
    private func canStart(_ requested: WriteOperation) -> Bool {
        guard active else { return false }
        guard operation == nil else {
            // Preserve the single in-flight write/no-queue contract. An enabled
            // peer control gives an explicit response rather than losing a tap.
            if operation != requested { message = Self.pendingMessage }
            return false
        }
        return true
    }
    private func run(
        _ requested: WriteOperation, exitEditing: Bool = false,
        _ action: @escaping @Sendable () async throws -> Void
    ) {
        guard confirmation == nil, canStart(requested) else { return }
        operation = requested; message = nil
        let token = generation
        mutation = Task { [weak self] in
            do {
                try await action()
                guard let self, self.active, self.generation == token, !Task.isCancelled else {
                    return
                }
                if exitEditing { self.selection = []; self.editing = false }
                self.finish(token)
            } catch { self?.finish(token, error: error) }
        }
    }
    private func endOperation() {
        operation = nil; mutation = nil
        if message == Self.pendingMessage { message = nil }
    }
    private func finish(_ token: Int, error: Error? = nil) {
        guard active, generation == token else { return }
        endOperation()
        verifyMissing()
        if let error, !(error is CancellationError), !Task.isCancelled {
            message = cartFailureMessage(error)
        }
    }
}

func cartFailureMessage(_ error: Error) -> String {
    guard let error = error as? ShoppingCartFailure else { return "价格和库存核验失败，请重试；购物车未修改" }
    switch error {
    case .invalidMoney: return "商品金额异常，购物车未修改"
    case .invalidQuantity: return "数量无效，购物车未修改"
    case .unavailable: return "商品或规格已失效，原购物车保留"
    case .insufficientStock(let count): return "库存不足，当前可售\(count)件，购物车未修改"
    case .priceChanged: return "价格再次变化，请重新核验确认"
    case .missingLine, .staleRevision: return "购物车已变化，请重新操作"
    case .readFailed: return "购物车读取失败，请重试"
    case .writeFailed: return "购物车保存失败，原数据保留，请重试"
    }
}
