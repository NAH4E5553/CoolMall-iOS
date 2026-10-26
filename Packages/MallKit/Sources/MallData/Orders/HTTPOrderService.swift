import Foundation
import MallCore

/// Three explicitly allowed reads. GET order/info/confirm is a write and is never called here.
public final class HTTPOrderService: OrdersLoading, CheckoutLoading, Sendable {
    private let environment: APIEnvironment
    private let session: any AccountReadAuthorizing
    private let transport: any ProductDetailTransport
    public convenience init(environment: APIEnvironment, session: SessionCoordinator) {
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
    public func loadOrders(accountID: Int64, filter: OrderFilter, page: Int, pageSize: Int)
        async throws
        -> NumberedPage<OrderSnapshot>
    {
        guard page > 0, (1...100).contains(pageSize) else {
            throw PageReadFailure.invalidConfiguration
        }
        struct Query: Encodable { let page: Int; let size: Int; let status: [Int]? }
        return try await read(
            accountID: accountID, path: "order/info/page",
            body: JSONEncoder().encode(
                Query(
                    page: page, size: pageSize,
                    status: filter.wireStatuses))
        ) { bytes in
            try CouponPageDecoder.page(bytes, requestedPage: page, size: pageSize) {
                (dto: OrderDTO) in try dto.value(accountID: accountID)
            }
        }
    }
    public func loadOrder(accountID: Int64, orderID: Int64) async throws -> OrderSnapshot {
        guard orderID > 0 else { throw PageReadFailure.invalidConfiguration }
        return try await read(
            accountID: accountID, path: "order/info/info?id=\(orderID)", body: nil
        ) {
            bytes in
            let dto: OrderDTO = try Self.payload(bytes)
            guard dto.id == orderID else { throw PageReadFailure.invalidResponse }
            return try dto.value(accountID: accountID)
        }
    }
    public func loadCheckout(accountID: Int64) async throws -> CheckoutContext {
        try await read(accountID: accountID, path: "page/confirmOrder", body: nil) { bytes in
            struct ContextDTO: Decodable {
                let defaultAddress: AddressDTO?; let userCoupon: [OwnedCouponDTO]?
            }
            let dto: ContextDTO = try Self.payload(bytes)
            let coupons = try dto.userCoupon?.map {
                try $0.value(availabilityContext: .checkoutCandidate)
            }
            guard coupons.map({ Set($0.map(\.id)).count == $0.count }) ?? true else {
                throw PageReadFailure.invalidResponse
            }
            return try CheckoutContext(
                defaultAddress: dto.defaultAddress?.value(), coupons: coupons)
        }
    }
    private static func payload<T: Decodable>(_ bytes: Data) throws -> T {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(EnvelopeHeader.self, from: bytes) else {
            throw PageReadFailure.invalidResponse
        }
        guard header.code == 1000 else { throw PageReadFailure.businessCode(header.code) }
        guard let value = try? decoder.decode(Envelope<T>.self, from: bytes).data else {
            throw PageReadFailure.invalidResponse
        }
        return value
    }
    private func read<T: Sendable>(
        accountID: Int64, path: String, body: Data?,
        decode: (Data) throws -> T
    ) async throws -> T {
        guard accountID > 0 else { throw PageReadFailure.authenticationRequired }
        var request = try CouponHTTP.request(environment, path: path)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        let context = try await session.authorization(
            accountID: accountID,
            environmentURL: environment.baseURL)
        try Task.checkCancellation()
        request.setValue(context.token, forHTTPHeaderField: "Authorization")
        do {
            let bytes = try await CouponHTTP.body(request, transport: transport)
            let value = try decode(bytes)
            try await session.validateAuthorization(context); try Task.checkCancellation()
            return value
        } catch {
            try await session.validateAuthorization(context)
            if error is CancellationError || error is PageReadFailure { throw error }
            throw PageReadFailure.invalidResponse
        }
    }
}
private struct OrderDTO: Decodable {
    let id: Int64
    let status: Int
    let userId: Int64?
    let orderNum: String?
    let title: String?
    let createTime: String?
    let payTime: String?
    let price: Decimal?
    let discountPrice: Decimal?
    let payType: Int?
    let remark: String?
    let closeRemark: String?
    let address: HistoricalAddressDTO?
    let goodsList: [OrderLineDTO]?
    func value(accountID: Int64) throws -> OrderSnapshot {
        guard id > 0, userId.map({ $0 == accountID }) ?? true else {
            throw PageReadFailure.invalidResponse
        }
        let lines = try goodsList?.map { try $0.value(orderID: id) }
        guard lines.map({ Set($0.map(\.id)).count == $0.count }) ?? true else {
            throw PageReadFailure.invalidResponse
        }
        return OrderSnapshot(
            id: id, number: trimmed(orderNum), status: status, title: trimmed(title),
            createdAt: trimmed(createTime), paidAt: trimmed(payTime),
            address: address?.value, lines: lines,
            amounts: price.flatMap { price in
                discountPrice.flatMap { try? OrderAmounts(subtotalYuan: price, discountYuan: $0) }
            }, payType: payType, remark: trimmed(remark), closeRemark: trimmed(closeRemark))
    }
}
private struct OrderLineDTO: Decodable {
    struct Goods: Decodable { let title: String?; let mainPic: String? }
    struct Specification: Decodable { let name: String? }
    let id: Int64
    let orderId: Int64?
    let count: Int64
    let price: Decimal?
    let goodsInfo: Goods?
    let spec: Specification?
    func value(orderID: Int64) throws -> OrderLineSnapshot {
        guard id > 0, count > 0, orderId.map({ $0 == orderID }) ?? true else {
            throw PageReadFailure.invalidResponse
        }
        let image = goodsInfo?.mainPic.flatMap(URL.init(string:)).flatMap {
            $0.scheme?.lowercased() == "https" && $0.host?.isEmpty == false ? $0 : nil
        }
        return OrderLineSnapshot(
            id: id, title: trimmed(goodsInfo?.title),
            specification: trimmed(spec?.name), imageURL: image, quantity: count,
            unitPriceYuan: price.flatMap { try? CartMoney(yuan: $0).yuan })
    }
}
private struct HistoricalAddressDTO: Decodable {
    let contact: String?; let phone: String?; let province: String?; let city: String?
    let district: String?; let address: String?; let isDefault: Bool?
    var value: OrderAddressSnapshot {
        OrderAddressSnapshot(
            contact: trimmed(contact), phone: trimmed(phone),
            location: [province, city, district, address].compactMap(trimmed).joined(
                separator: " "), isDefault: isDefault
        )
    }
}
private func trimmed(_ value: String?) -> String? {
    value.flatMap {
        let text = $0.trimmingCharacters(in: .whitespacesAndNewlines);
        return text.isEmpty ? nil : text
    }
}
