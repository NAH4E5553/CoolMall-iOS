import Foundation
import MallCore
import Observation

/// Detail-owned add operation. A confirmed price authorizes that price only;
/// each confirmation re-reads the server and the store rechecks the latest C.
@MainActor @Observable
final class ProductCartViewModel {
    struct Intent {
        let item: CartItemID
        let quantity: Int64
        let displayedPrice: CartMoney
        let operationID: UUID
    }
    struct Confirmation {
        let intent: Intent
        let old: CartMoney?
        let new: CartMoney
        let resultingQuantity: Int64
        let previouslyConfirmed: CartMoney?
        var text: String {
            (previouslyConfirmed.map { "刚确认\($0.formatted)，报价再次变化。" } ?? "")
                + "本次选择价\(intent.displayedPrice.formatted)。"
                + (old.map { "车内原价\($0.formatted)。" } ?? "")
                + "最新单价\(new.formatted)，用于该规格全部\(resultingQuantity)件，调整后该行合计\((try? new.multiplied(by: resultingQuantity).formatted) ?? "金额异常")。确认后会再次核验。"
        }
    }
    private let store: any ShoppingCart
    private let verifier: any CartProductChecking
    private(set) var busy = false
    private(set) var confirmation: Confirmation?
    private(set) var message: String?
    private(set) var success = 0
    private var active = false
    private var generation = 0
    private var task: Task<Void, Never>?
    init(store: any ShoppingCart, verifier: any CartProductChecking) {
        self.store = store; self.verifier = verifier
    }
    func setActive(_ value: Bool) {
        active = value
        if !value { cancel() }
    }
    func cancel() {
        generation += 1; task?.cancel(); task = nil; busy = false; confirmation = nil
    }
    func add(specification: ProductSpecification, quantity: Int64) {
        guard active, !busy, confirmation == nil else { return }
        guard specification.stock > 0, quantity > 0, quantity <= specification.stock else {
            message = "所选规格库存不足，购物车未修改"; return
        }
        do {
            let price = try CartMoney(yuan: specification.priceYuan)
            start(
                .init(
                    item: .init(
                        productID: specification.productID, specificationID: specification.id),
                    quantity: quantity, displayedPrice: price, operationID: UUID()),
                acceptedPrice: nil)
        } catch { message = "商品金额异常，未加入购物车" }
    }
    func confirmPrice() {
        guard let confirmation else { return }
        start(confirmation.intent, acceptedPrice: confirmation.new)
    }
    private func start(_ intent: Intent, acceptedPrice: CartMoney?) {
        guard active, !busy else { return }
        confirmation = nil; message = nil; busy = true
        generation += 1
        let token = generation
        task = Task { [weak self, store, verifier] in
            do {
                guard intent.quantity > 0 else { throw ShoppingCartFailure.invalidQuantity }
                let check = try await verifier.check(productID: intent.item.productID)
                try Task.checkCancellation()
                let quote = try check.quote(for: intent.item)
                let snapshot = try await store.current()
                try Task.checkCancellation()
                let oldLine = snapshot.lines.first { $0.id == intent.item }
                let (count, overflow) = (oldLine?.quantity ?? 0).addingReportingOverflow(
                    intent.quantity)
                guard !overflow else { throw ShoppingCartFailure.invalidQuantity }
                guard count <= quote.stock else {
                    throw ShoppingCartFailure.insufficientStock(available: quote.stock)
                }
                _ = try quote.price.multiplied(by: count)
                guard let self, self.active, self.generation == token else { return }
                let differsFromInitial =
                    quote.price != intent.displayedPrice
                    || oldLine.map { $0.unitPrice != quote.price } == true
                let needsConfirmation =
                    acceptedPrice.map { $0 != quote.price } ?? differsFromInitial
                if needsConfirmation {
                    self.confirmation = .init(
                        intent: intent, old: oldLine?.unitPrice,
                        new: quote.price, resultingQuantity: count,
                        previouslyConfirmed: acceptedPrice)
                    self.busy = false; self.task = nil; return
                }
                try await store.add(
                    quantity: intent.quantity, quote: quote, confirmedPrice: acceptedPrice,
                    operationID: intent.operationID)
                guard self.active, self.generation == token, !Task.isCancelled else { return }
                self.busy = false; self.task = nil; self.success += 1; self.message = "已加入购物车"
            } catch {
                guard let self, self.active, self.generation == token else { return }
                self.busy = false; self.task = nil
                if !(error is CancellationError), !Task.isCancelled {
                    self.message = Self.description(error)
                }
            }
        }
    }
    private static func description(_ error: Error) -> String {
        switch error as? ShoppingCartFailure {
        case .insufficientStock(let count): return "库存不足，当前可售\(count)件；购物车未修改"
        case .priceChanged: return "购物车价格再次变化，请重新加购确认"
        case .unavailable: return "商品或规格已失效，购物车未修改"
        case .invalidMoney: return "商品金额异常，购物车未修改"
        case .invalidQuantity: return "数量无效，购物车未修改"
        case .writeFailed: return "保存失败，原购物车保留，请重试"
        case .readFailed: return "购物车读取失败，请重试"
        default: return "价格和库存核验失败，购物车未修改，请重试"
        }
    }
}
