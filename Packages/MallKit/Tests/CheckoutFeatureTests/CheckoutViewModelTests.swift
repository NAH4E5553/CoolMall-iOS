import Foundation
import MallCore
import Testing
@testable import CheckoutFeature

@MainActor struct CheckoutViewModelTests {
    static func intent() throws -> BuyNowIntent {
        try BuyNowIntent(
            product: ProductDetailSnapshot(
                id: 9, title: "商品", subtitle: nil, priceYuan: 999,
                sold: 0, isAvailable: true, imageURLs: [], contentImageURLs: []),
            specification: ProductSpecification(
                id: 4, productID: 9, name: "规格", priceYuan: 999, stock: 3, imageURLs: []),
            quantity: 2)
    }
    static func address(_ id: Int64) -> ShippingAddress {
        ShippingAddress(id: id, value: ShippingAddressInput(contact: "联系人\(id)"))
    }
    static func coupon(_ id: Int64) -> UserCoupon {
        UserCoupon(
            id: id, title: "券", description: "候选", amountYuan: 30, minimumSpendYuan: 299,
            startTime: "2020-01-01T00:00:00Z", endTime: "2030-01-01T00:00:00Z", type: 0, status: 1,
            useStatus: 0)
    }
    @MainActor final class Loader: CheckoutLoading {
        var hold = false
        var fail = false
        var calls = 0
        var context = CheckoutContext(defaultAddress: address(1), coupons: [coupon(1)])
        var gate: CheckedContinuation<CheckoutContext, Error>?
        func loadCheckout(accountID: Int64) async throws -> CheckoutContext {
            calls += 1
            if hold { hold = false; return try await withCheckedThrowingContinuation { gate = $0 } }
            if fail { throw PageReadFailure.timeout }; return context
        }
    }
    func wait(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() };
        Issue.record("gate did not arrive")
    }
    @Test func subtotalStaysUnchangedWhenCouponSelectedAndRefreshPreservesAddress() async throws {
        let loader = Loader();
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        await model.activate(true); model.chooseCoupon(Self.coupon(1));
        model.addressSelection()(Self.address(7))
        await model.refresh()
        #expect(model.address?.id == 7); #expect(model.selectedCoupon?.id == 1)
        #expect(model.intent.subtotalYuan == 1998); #expect(model.loaded); model.stop()
    }
    @Test func lateDefaultDoesNotOverwriteUserSelectionAndOldCallbackCannotChangeNewVisit()
        async throws
    {
        let loader = Loader(); loader.hold = true
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        let task = Task { await model.activate(true) }; await wait { loader.gate != nil }
        let old = model.addressSelection(); old(Self.address(7))
        loader.gate?.resume(returning: loader.context); await task.value
        #expect(model.address?.id == 7)
        model.stop(); await model.activate(true); old(Self.address(8));
        #expect(model.address?.id == 7)
        model.addressSelection()(Self.address(9)); #expect(model.address?.id == 9); model.stop()
    }
    @Test func changedOrMissingCouponIsClearedWithoutInventedDeduction() async throws {
        let loader = Loader();
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        await model.activate(true); model.chooseCoupon(Self.coupon(1))
        loader.context = CheckoutContext(defaultAddress: nil, coupons: nil); await model.refresh()
        #expect(model.selectedCoupon == nil); #expect(model.coupons == nil);
        #expect(model.notice != nil)
        #expect(model.intent.subtotalYuan == 1998); model.stop()
    }
    @MainActor final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }
    @Test func unchangedCouponCrossingExpiryIsClearedOnlyAfterSuccessfulRefresh() async throws {
        let end = try #require(ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z"))
        let clock = Clock(end.addingTimeInterval(-1)); let loader = Loader()
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, now: { clock.date })
        await model.activate(true); model.chooseCoupon(Self.coupon(1)); await model.refresh()
        #expect(model.selectedCoupon?.id == 1)
        clock.date = end; loader.fail = true; await model.refresh()
        #expect(model.selectedCoupon?.id == 1); #expect(model.failure == .timeout)
        loader.fail = false; await model.refresh()
        #expect(model.selectedCoupon == nil); #expect(model.notice != nil)
        #expect(model.intent.subtotalYuan == 1998)
        model.chooseCoupon(Self.coupon(1)); #expect(model.selectedCoupon == nil); model.stop()
    }
    @Test func refreshFailurePreservesSelectionsAndRetryIsExplicit() async throws {
        let loader = Loader();
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        await model.activate(true); model.chooseCoupon(Self.coupon(1)); loader.fail = true
        await model.refresh(); #expect(model.failure == .timeout); #expect(model.address?.id == 1)
        #expect(model.selectedCoupon?.id == 1); #expect(loader.calls == 2)
        loader.fail = false; model.retry(); await model.activate(true)
        // Loaded contexts refresh through the explicit retry action, not an automatic replay.
        #expect(model.failure == nil); #expect(loader.calls == 3); model.stop()
    }
    @Test func leavingRejectsLateContextAndInvalidCouponCannotBeSelected() async throws {
        let loader = Loader(); loader.hold = true
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        let task = Task { await model.activate(true) }; await wait { loader.gate != nil }
        model.stop(); loader.gate?.resume(returning: loader.context); await task.value
        #expect(!model.loaded); #expect(model.address == nil)
        await model.activate(true); model.chooseCoupon(Self.coupon(2));
        #expect(model.selectedCoupon == nil)
        model.stop()
    }
    @MainActor final class Creator: OrderCreating {
        var calls = 0
        var known: Int64?
        func knownCreatedOrder(accountID: Int64, intentID: UUID) async throws -> Int64? { known }
        var error: OrderWriteFailure?
        var hold = false
        var gate: CheckedContinuation<Int64, Error>?
        func createOrder(accountID: Int64, input: OrderCreation) async throws -> Int64 {
            calls += 1
            if hold { return try await withCheckedThrowingContinuation { gate = $0 } }
            if let error { throw error }; return 71
        }
    }
    @Test func createOwnsSelectionsAndDoubleClickCannotSendTwice() async throws {
        let loader = Loader(), creator = Creator(); creator.hold = true
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, creator: creator)
        await model.activate(true); model.chooseCoupon(Self.coupon(1))
        #expect(model.estimate?.totalYuan == 1968)
        let task = Task { await model.submit() }; await wait { creator.gate != nil }
        #expect(await model.submit() == nil); #expect(creator.calls == 1)
        model.toggleCoupon(Self.coupon(1)); #expect(model.selectedCoupon?.id == 1)
        creator.gate?.resume(returning: 71); #expect(await task.value == 71)
        #expect(!model.canSubmit); #expect(model.writeLocked)
    }
    @Test func unknownCreateLocksWhileRejectedMessageRemainsRetryableAndLateSuccessCannotNavigate()
        async throws
    {
        let loader = Loader(), creator = Creator()
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, creator: creator)
        await model.activate(true); creator.error = .rejected(code: 500, message: "库存不足")
        #expect(await model.submit() == nil); #expect(model.canSubmit)
        #expect(model.writeFailure?.message == "库存不足")
        creator.error = .unconfirmed; #expect(await model.submit() == nil);
        #expect(!model.canSubmit)
        let late = Creator(); late.hold = true
        let other = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, creator: late)
        await other.activate(true)
        let task = Task { await other.submit() }; await wait { late.gate != nil }
        other.stop(); late.gate?.resume(returning: 71); #expect(await task.value == nil)
    }

    @Test func establishedOrderRestoresBeforeUnavailableContextOrCouponValidation() async throws {
        let loader = Loader(); loader.fail = true
        let creator = Creator(); creator.known = 71
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader, creator: creator)
        await model.activate(true)
        #expect(model.recoveredOrderID == 71); #expect(model.writeLocked)
        #expect(loader.calls == 0); #expect(creator.calls == 0)
    }

    @Test func couponExpiringDuringWriteCannotMutateSubmittedSelectionOnRepeatedTap() async throws {
        let end = try #require(ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z"))
        let clock = Clock(end.addingTimeInterval(-1)), loader = Loader(), creator = Creator()
        creator.hold = true
        let model = CheckoutViewModel(
            accountID: 1, intent: try Self.intent(), loader: loader,
            now: { clock.date }, creator: creator)
        await model.activate(true); model.chooseCoupon(Self.coupon(1))
        let task = Task { await model.submit() }; await wait { creator.gate != nil }
        clock.date = end
        #expect(await model.submit() == nil); #expect(creator.calls == 1)
        #expect(model.selectedCoupon?.id == 1); #expect(model.writeFailure == nil)
        creator.gate?.resume(returning: 71); #expect(await task.value == 71)
    }

    @Test func sparseCouponTogglesOffAndDefaultSelectionHasNoDeduction() async throws {
        let loader = Loader()
        let coupon = UserCoupon(
            id: 7, title: "候选", description: "", amountYuan: 30,
            minimumSpendYuan: 299, startTime: nil, endTime: nil, type: 0, status: 1,
            useStatus: nil, availabilityContext: .checkoutCandidate)
        loader.context = CheckoutContext(defaultAddress: Self.address(1), coupons: [coupon])
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        await model.activate(true)
        #expect(model.selectedCoupon == nil); #expect(model.estimate?.totalYuan == 1998)
        #expect(model.couponUnavailableReason(coupon) == nil)
        model.toggleCoupon(coupon)
        #expect(model.selectedCoupon?.id == 7); #expect(model.estimate?.totalYuan == 1968)
        model.toggleCoupon(coupon)
        #expect(model.selectedCoupon == nil); #expect(model.estimate?.discountYuan == 0)
        #expect(model.estimate?.totalYuan == 1998); model.stop()
    }
    @Test func unavailableCandidatesExplainActualRestriction() throws {
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: Loader())
        func coupon(minimum: Decimal? = 9999, used: Int? = nil) -> UserCoupon {
            UserCoupon(
                id: 7, title: "候选", description: "", amountYuan: 30,
                minimumSpendYuan: minimum, startTime: nil, endTime: nil,
                type: 0, status: 1, useStatus: used, availabilityContext: .checkoutCandidate)
        }
        #expect(model.couponUnavailableReason(coupon()) == "未满9999元")
        #expect(model.couponUnavailableReason(coupon(minimum: nil)) == "门槛待确认")
        #expect(model.couponUnavailableReason(coupon(used: 1)) == "已使用")
        #expect(model.couponUnavailableReason(coupon(used: 2)) == "已过期")
    }

    @Test func refreshingCandidatesRejectsStaleToggleAndClearsChangedChoice() async throws {
        let loader = Loader()
        let model = CheckoutViewModel(accountID: 1, intent: try Self.intent(), loader: loader)
        await model.activate(true); model.chooseCoupon(Self.coupon(1))
        loader.hold = true
        let refresh = Task { await model.refresh() }
        await wait { loader.gate != nil }
        #expect(model.loading)
        model.toggleCoupon(Self.coupon(1))
        #expect(model.selectedCoupon?.id == 1)
        let changed = UserCoupon(
            id: 1, title: "new", description: "changed", amountYuan: 50,
            minimumSpendYuan: 299, startTime: nil, endTime: nil, type: 0, status: 1,
            useStatus: nil, availabilityContext: .checkoutCandidate)
        loader.gate?.resume(
            returning: CheckoutContext(defaultAddress: Self.address(1), coupons: [changed]))
        await refresh.value
        #expect(!model.loading); #expect(model.selectedCoupon == nil)
        #expect(model.estimate?.discountYuan == 0); #expect(model.estimate?.totalYuan == 1998)
        model.stop()
    }

    actor CleanupCart: ShoppingCart {
        nonisolated let scope: CartScope
        var snapshot: ShoppingCartSnapshot
        var removes = 0; var fail = false; var hold = false
        var gate: CheckedContinuation<Void, Never>?
        init(_ snapshot: ShoppingCartSnapshot) { self.snapshot = snapshot; scope = snapshot.scope }
        func configure(fail: Bool = false, hold: Bool = false) {
            self.fail = fail; self.hold = hold
        }
        func release() { gate?.resume(); gate = nil }
        func change() {
            snapshot = .init(scope: scope, revision: snapshot.revision + 1, lines: snapshot.lines)
        }
        func current() async -> ShoppingCartSnapshot {
            if hold { hold = false; await withCheckedContinuation { gate = $0 } }
            return snapshot
        }
        func observe() -> AsyncStream<ShoppingCartSnapshot> {
            AsyncStream {
                $0.yield(snapshot); $0.finish()
            }
        }
        func remove(_ items: Set<CartItemID>, expectedRevision: UInt64) throws {
            try Task.checkCancellation()
            guard expectedRevision == snapshot.revision else {
                throw ShoppingCartFailure.staleRevision
            }
            if fail { throw ShoppingCartFailure.writeFailed }
            removes += 1
            snapshot = .init(
                scope: scope, revision: snapshot.revision + 1,
                lines: snapshot.lines.filter { !items.contains($0.id) })
        }
        func add(quantity: Int64, quote: CartQuote, confirmedPrice: CartMoney?, operationID: UUID)
            throws
        { throw ShoppingCartFailure.unavailable }
        func increase(
            _ item: CartItemID, quote: CartQuote, confirmedPrice: CartMoney?,
            expectedRevision: UInt64
        ) throws { throw ShoppingCartFailure.unavailable }
        func decrease(_ item: CartItemID, expectedRevision: UInt64) throws {
            throw ShoppingCartFailure.unavailable
        }
    }
    static func cartInput() throws -> (CheckoutIntent, ShoppingCartSnapshot) {
        let product = ProductDetailSnapshot(
            id: 9, title: "商品", subtitle: nil, priceYuan: 100,
            sold: 0, isAvailable: true, imageURLs: [], contentImageURLs: [])
        let specs = (4...6).map {
            ProductSpecification(
                id: Int64($0), productID: 9,
                name: "spec-\($0)", priceYuan: 100, stock: 5, imageURLs: [])
        }
        let quotes = try specs.map {
            CartQuote(
                productID: 9, specificationID: $0.id, title: product.title,
                specification: $0.name, imageURL: nil, price: try CartMoney(yuan: 100), stock: 5)
        }
        let snapshot = ShoppingCartSnapshot(
            scope: .init(environment: "test", accountID: nil), revision: 0,
            lines: quotes.map { CartLine(quote: $0, quantity: 1) })
        let input = try CheckoutIntent(
            cart: snapshot, selection: [quotes[0].id, quotes[1].id],
            checks: [
                9: .init(
                    productID: 9, isAvailable: true, quotes: quotes, product: product,
                    specifications: specs)
            ])
        return (input, snapshot)
    }
    @Test func confirmedCartOrderRemovesOnlySelectedRowsAndCanRecoverWithoutRecreation()
        async throws
    {
        for recovering in [false, true] {
            let (intent, snapshot) = try Self.cartInput();
            let cart = CleanupCart(snapshot), creator = Creator()
            if recovering { creator.known = 71 }
            let model = CheckoutViewModel(
                accountID: 1, intent: intent, loader: Loader(), creator: creator, cart: cart)
            await model.activate(true)
            if recovering {
                #expect(model.recoveredOrderID == 71); #expect(creator.calls == 0)
            } else {
                #expect(await model.submit() == 71); #expect(creator.calls == 1)
            }
            #expect(await cart.removes == 1)
            let value = await cart.current(); #expect(value.lines.map(\.specificationID) == [6])
            #expect(!model.cartCleanupFailed); #expect(!model.canSubmit)
            #expect(await model.submit() == nil); #expect(await cart.removes == 1)
            model.stop()
        }
    }
    @Test func rejectedAndUnknownOrdersNeverRemoveCart() async throws {
        for error: OrderWriteFailure in [.rejected(code: 500, message: "库存不足"), .unconfirmed] {
            let (intent, snapshot) = try Self.cartInput();
            let cart = CleanupCart(snapshot), creator = Creator()
            creator.error = error
            let model = CheckoutViewModel(
                accountID: 1, intent: intent, loader: Loader(), creator: creator, cart: cart)
            await model.activate(true); #expect(await model.submit() == nil)
            #expect(await cart.removes == 0); #expect(await cart.current().lines.count == 3)
            #expect(model.writeFailure == error); model.stop()
        }
    }
    @Test func changedCartOrCleanupFailureKeepsCreatedOrderLockedAndPreservesData() async throws {
        for changed in [false, true] {
            let (intent, snapshot) = try Self.cartInput();
            let cart = CleanupCart(snapshot), creator = Creator()
            let model = CheckoutViewModel(
                accountID: 1, intent: intent, loader: Loader(), creator: creator, cart: cart)
            await model.activate(true)
            if changed { await cart.change() } else { await cart.configure(fail: true) }
            #expect(await model.submit() == 71); #expect(model.writeLocked)
            #expect(model.cartCleanupFailed); #expect(await cart.removes == 0)
            #expect(await cart.current().lines.count == 3); #expect(creator.calls == 1)
            #expect(await model.submit() == nil); model.stop()
        }
    }
    @Test func leavingDuringCleanupRejectsLateNavigationAndCartDeletion() async throws {
        let (intent, snapshot) = try Self.cartInput();
        let cart = CleanupCart(snapshot), creator = Creator()
        let model = CheckoutViewModel(
            accountID: 1, intent: intent, loader: Loader(), creator: creator, cart: cart)
        await model.activate(true); await cart.configure(hold: true)
        let submit = Task { await model.submit() }
        for _ in 0..<1000 { if await cart.gate != nil { break }; await Task.yield() }
        #expect(await cart.gate != nil); model.stop(); await cart.release()
        #expect(await submit.value == nil); #expect(await cart.removes == 0)
        #expect(await cart.current().lines.count == 3)
    }

    @Test func recoveryLeavingDuringCleanupCannotDeleteOrNavigate() async throws {
        let (intent, snapshot) = try Self.cartInput()
        let cart = CleanupCart(snapshot), creator = Creator(); creator.known = 71
        await cart.configure(hold: true)
        let model = CheckoutViewModel(
            accountID: 1, intent: intent, loader: Loader(), creator: creator, cart: cart)
        let activation = Task { await model.activate(true) }
        for _ in 0..<1000 { if await cart.gate != nil { break }; await Task.yield() }
        #expect(await cart.gate != nil); model.stop(); await cart.release(); await activation.value
        #expect(model.recoveredOrderID == nil); #expect(await cart.removes == 0)
        #expect(creator.calls == 0); #expect(await cart.current().lines.count == 3)
    }
    @Test func missingOrDifferentScopeCartCannotSubmitOrDelete() async throws {
        let (intent, snapshot) = try Self.cartInput()
        for missing in [true, false] {
            let other = ShoppingCartSnapshot(
                scope: .init(environment: "another", accountID: "2"), revision: 0,
                lines: snapshot.lines)
            let cart = CleanupCart(other), creator = Creator()
            let model = CheckoutViewModel(
                accountID: 1, intent: intent, loader: Loader(), creator: creator,
                cart: missing ? nil : cart)
            await model.activate(true); #expect(!model.canSubmit)
            #expect(await model.submit() == nil); #expect(creator.calls == 0)
            #expect(await cart.removes == 0); model.stop()
        }
    }

}
