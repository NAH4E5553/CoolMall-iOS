import Foundation
import MallCore

/// App-lifetime write ownership. Unknown attempts remain locked across page recreation.
/// There is no backend idempotency contract or cross-process replay protection.
public actor HTTPOrderTransactions: OrderCreating, OrderCancelling {
    private enum Operation: Hashable { case create(Int64, UUID); case cancel(Int64, Int64) }
    private enum Outcome { case pending, unknown, created(Int64), cancelled }
    private let environment: APIEnvironment
    private let session: any AccountReadAuthorizing
    private let transport: any ProductDetailTransport
    private var outcomes: [Operation: Outcome] = [:]
    public init(environment: APIEnvironment, session: SessionCoordinator) {
        self.init(
            environment: environment, session: session,
            transport: URLSessionTransport(resourceTimeout: environment.resourceTimeout))
    }
    init(
        environment: APIEnvironment, session: any AccountReadAuthorizing,
        transport: any ProductDetailTransport
    ) {
        self.environment = environment; self.session = session; self.transport = transport
    }
    public func knownCreatedOrder(accountID: Int64, intentID: UUID) async throws -> Int64? {
        let context = try await authorization(accountID)
        try await validate(context)
        if case .created(let id) = outcomes[.create(accountID, intentID)] { return id }
        return nil
    }
    public func createOrder(accountID: Int64, input: OrderCreation) async throws -> Int64 {
        let key = Operation.create(accountID, input.intent.id)
        let context = try await authorization(accountID)
        if let outcome = outcomes[key] {
            switch outcome {
            case .created(let id): return id
            case .pending: throw OrderWriteFailure.busy
            default: throw OrderWriteFailure.unconfirmed
            }
        }
        guard input.addressID > 0 else { throw OrderWriteFailure.invalidInput }
        _ = try CheckoutEstimate(subtotalYuan: input.intent.subtotalYuan, coupon: input.coupon)
        struct Goods: Encodable { let id: Int64; let title: String; let mainPic: String? }
        struct Spec: Encodable {
            let id: Int64; let goodsId: Int64; let name: String; let price: Int64
            let stock: Int64; let images: [String]
        }
        struct Selected: Encodable {
            let goodsId: Int64; let count: Int64; let goodsInfo: Goods; let spec: Spec
        }
        struct Command: Encodable {
            let addressId: Int64; let goodsList: [Selected]; let couponId: Int64?
            let remark: String; let title: String
        }
        struct Body: Encodable { let data: Command }
        let selected = try input.intent.lines.map { line in
            // Preserve Android's integral-yuan SKU contract; never round a price.
            guard let wirePrice = Int64(NSDecimalNumber(decimal: line.unitPriceYuan).stringValue)
            else { throw OrderWriteFailure.invalidInput }
            return Selected(
                goodsId: line.productID, count: line.quantity,
                goodsInfo: Goods(
                    id: line.productID, title: line.title,
                    mainPic: line.productImageURL?.absoluteString),
                spec: Spec(
                    id: line.specificationID, goodsId: line.productID,
                    name: line.specification, price: wirePrice, stock: line.stock,
                    images: line.specificationImages.map(\.absoluteString)))
        }
        let bytes = try JSONEncoder().encode(
            Body(
                data: Command(
                    addressId: input.addressID,
                    goodsList: selected, couponId: input.coupon?.id, remark: input.remark,
                    title: "购买商品")))
        let response = try await write(
            key, context: context, path: "order/info/create", body: bytes)
        struct Receipt: Decodable { let id: Int64; let userId: Int64? }
        guard let receipt = try? JSONDecoder().decode(Envelope<Receipt>.self, from: response).data,
            receipt.id > 0, receipt.userId.map({ $0 == accountID }) ?? true
        else { outcomes[key] = .unknown; throw OrderWriteFailure.unconfirmed }
        outcomes[key] = .created(receipt.id)
        try await validate(context)
        return receipt.id
    }
    public func cancelOrder(accountID: Int64, orderID: Int64, reason: OrderCancelReason)
        async throws
    {
        guard orderID > 0, reason.id > 0,
            !reason.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw OrderWriteFailure.invalidInput }
        let context = try await authorization(accountID)
        let key = Operation.cancel(accountID, orderID)
        if let outcome = outcomes[key] {
            switch outcome {
            case .cancelled: return
            case .pending: throw OrderWriteFailure.busy
            default: throw OrderWriteFailure.unconfirmed
            }
        }
        struct Command: Encodable { let orderId: Int64; let remark: String }
        let body = try JSONEncoder().encode(Command(orderId: orderID, remark: reason.name))
        let response = try await write(key, context: context, path: "order/info/cancel", body: body)
        guard (try? JSONDecoder().decode(Envelope<Bool>.self, from: response).data) == true else {
            outcomes[key] = .unknown; throw OrderWriteFailure.unconfirmed
        }
        outcomes[key] = .cancelled
        try await validate(context)
    }
    public func loadCancelReasons(accountID: Int64) async throws -> [OrderCancelReason] {
        let context = try await authorization(accountID)
        var request = try CouponHTTP.request(environment, path: "dict/info/data")
        request.httpBody = Data(#"{"types":["orderCancelReason"]}"#.utf8)
        request.setValue(context.token, forHTTPHeaderField: "Authorization")
        let bytes: Data
        do { bytes = try await CouponHTTP.body(request, transport: transport) } catch {
            try await validate(context); throw error
        }
        try await validate(context); try Task.checkCancellation()
        try Self.checkHeader(bytes)
        struct Reason: Decodable { let id: Int64; let name: String }
        struct Payload: Decodable { let orderCancelReason: [Reason] }
        guard
            let rows = try? JSONDecoder().decode(Envelope<Payload>.self, from: bytes).data?
                .orderCancelReason,
            Set(rows.map(\.id)).count == rows.count,
            rows.allSatisfy({
                $0.id > 0 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { throw PageReadFailure.invalidResponse }
        return rows.map { OrderCancelReason(id: $0.id, name: $0.name) }
    }
    private func authorization(_ accountID: Int64) async throws -> AccountReadContext {
        try Task.checkCancellation()
        guard accountID > 0 else { throw OrderWriteFailure.authenticationRequired }
        do {
            let context = try await session.authorization(
                accountID: accountID,
                environmentURL: environment.baseURL)
            try Task.checkCancellation(); return context
        } catch is CancellationError { throw CancellationError() } catch {
            throw OrderWriteFailure.authenticationRequired
        }
    }
    private func validate(_ context: AccountReadContext) async throws {
        do { try await session.validateAuthorization(context) } catch {
            if Task.isCancelled { throw CancellationError() }
            throw OrderWriteFailure.authenticationRequired
        }
    }
    private func write(_ key: Operation, context: AccountReadContext, path: String, body: Data)
        async throws -> Data
    {
        var request = try CouponHTTP.request(environment, path: path)
        request.httpBody = body;
        request.setValue(context.token, forHTTPHeaderField: "Authorization")
        try Task.checkCancellation()
        // There is no suspension between acquiring ownership and dispatch.
        outcomes[key] = .pending
        do {
            let bytes = try await CouponHTTP.body(request, transport: transport)
            do { try Self.checkHeader(bytes) } catch let failure as OrderWriteFailure {
                if case .rejected = failure { outcomes.removeValue(forKey: key) }
                throw failure
            }
            return bytes
        } catch {
            if case .pending = outcomes[key] { outcomes[key] = .unknown }
            try await validate(context)
            if error as? PageReadFailure == .authenticationRequired {
                throw OrderWriteFailure.authenticationRequired
            }
            if let failure = error as? OrderWriteFailure { throw failure }
            throw OrderWriteFailure.unconfirmed
        }
    }
    private static func checkHeader(_ bytes: Data) throws {
        struct Header: Decodable { let code: Int }
        struct Message: Decodable { let message: String? }
        guard let header = try? JSONDecoder().decode(Header.self, from: bytes) else {
            throw OrderWriteFailure.unconfirmed
        }
        guard header.code == 1000 else {
            let message = (try? JSONDecoder().decode(Message.self, from: bytes))?.message?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OrderWriteFailure.rejected(
                code: header.code,
                message: message?.isEmpty == false ? message : nil)
        }
    }
}
