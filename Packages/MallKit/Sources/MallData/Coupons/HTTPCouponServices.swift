import Foundation
import MallCore

/// Internal, ephemeral authorization snapshot. Credentials never cross the Data boundary.
struct AccountReadContext: Sendable {
    let accountID: Int64
    let generation: UInt64
    let token: String
    let environmentURL: URL
}
protocol AccountReadAuthorizing: Sendable {
    func authorization(accountID: Int64, environmentURL: URL) async throws -> AccountReadContext
    func validateAuthorization(_ context: AccountReadContext) async throws
}
extension SessionCoordinator: AccountReadAuthorizing {}

public final class HTTPUserCouponService: UserCouponsLoading, Sendable {
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
    public func loadCoupons(accountID: Int64, page: Int, pageSize: Int) async throws
        -> NumberedPage<UserCoupon>
    {
        guard accountID > 0 else { throw PageReadFailure.authenticationRequired }
        var request = try CouponHTTP.request(
            environment, path: "market/coupon/user/page", page: page, size: pageSize)
        struct Query: Encodable { let page: Int; let size: Int; let sort = "desc" }
        request.httpBody = try JSONEncoder().encode(Query(page: page, size: pageSize))
        let context = try await session.authorization(
            accountID: accountID, environmentURL: environment.baseURL)
        request.setValue(context.token, forHTTPHeaderField: "Authorization")
        do {
            let bytes = try await CouponHTTP.body(request, transport: transport)
            let result: NumberedPage<UserCoupon> = try CouponPageDecoder.page(
                bytes, requestedPage: page, size: pageSize
            ) { (dto: OwnedCouponDTO) in try dto.value() }
            try await session.validateAuthorization(context)
            return result
        } catch {
            // Validate failures too: an old account's network error cannot become the new page's error.
            try await session.validateAuthorization(context)
            throw error
        }
    }
}
public final class HTTPCouponProductsService: CouponProductsLoading, Sendable {
    private let environment: APIEnvironment
    private let transport: any ProductDetailTransport
    public convenience init(environment: APIEnvironment) {
        self.init(
            environment: environment,
            transport: URLSessionTransport(resourceTimeout: environment.resourceTimeout))
    }
    init(environment: APIEnvironment, transport: any ProductDetailTransport) {
        self.environment = environment; self.transport = transport
    }
    public func loadProducts(minimumPriceYuan: Decimal?, page: Int, pageSize: Int) async throws
        -> NumberedPage<CouponProductSummary>
    {
        if let minimumPriceYuan, minimumPriceYuan.isNaN || minimumPriceYuan < 0 {
            throw PageReadFailure.invalidConfiguration
        }
        var request = try CouponHTTP.request(
            environment, path: "goods/info/page", page: page, size: pageSize)
        struct Query: Encodable {
            let page: Int; let size: Int; let minPrice: String?
            let featured = false; let recommend = false
        }
        request.httpBody = try JSONEncoder().encode(
            Query(
                page: page, size: pageSize,
                minPrice: minimumPriceYuan.map { NSDecimalNumber(decimal: $0).stringValue }))
        let bytes = try await CouponHTTP.body(request, transport: transport)
        return try CouponPageDecoder.page(bytes, requestedPage: page, size: pageSize) {
            (dto: HomeProductDTO) in
            guard dto.id > 0, !dto.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                dto.price >= 0,
                (dto.sold ?? 0) >= 0
            else { throw PageReadFailure.invalidResponse }
            let url = dto.mainPic.flatMap(URL.init(string:)).flatMap {
                $0.scheme?.lowercased() == "https" && $0.host?.isEmpty == false ? $0 : nil
            }
            return CouponProductSummary(
                id: dto.id, title: dto.title, subtitle: dto.subTitle, imageURL: url,
                priceYuan: Decimal(dto.price), sold: dto.sold ?? 0)
        }
    }
}
enum CouponHTTP {
    static func request(_ environment: APIEnvironment, path: String, page: Int, size: Int) throws
        -> URLRequest
    {
        guard page > 0, (1...100).contains(size) else { throw PageReadFailure.invalidConfiguration }
        return try request(environment, path: path)
    }
    static func request(_ environment: APIEnvironment, path: String) throws -> URLRequest {
        let base = environment.baseURL
        guard base.scheme?.lowercased() == "https",
            base.host?.isEmpty == false, base.absoluteString.hasSuffix("/"), base.query == nil,
            base.fragment == nil, base.user == nil, base.password == nil,
            environment.requestTimeout > 0, environment.requestTimeout.isFinite,
            environment.resourceTimeout > 0, environment.resourceTimeout.isFinite,
            let url = URL(string: path, relativeTo: base)?.absoluteURL
        else { throw PageReadFailure.invalidConfiguration }
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: environment.requestTimeout)
        request.httpMethod = "POST";
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); return request
    }
    static func body(_ request: URLRequest, transport: any ProductDetailTransport) async throws
        -> Data
    {
        do {
            return try await APIClient.productBodyData(for: request, using: transport)
        } catch is CancellationError { throw CancellationError() } catch let error
            as ProductDetailLoadFailure
        {
            switch error {
            case .httpStatus(401), .httpStatus(403): throw PageReadFailure.authenticationRequired
            case .httpStatus(let code): throw PageReadFailure.httpStatus(code)
            case .timeout: throw PageReadFailure.timeout
            case .networkUnavailable: throw PageReadFailure.networkUnavailable
            default: throw PageReadFailure.invalidResponse
            }
        }
    }
}
enum CouponPageDecoder {
    private struct Body<T: Decodable>: Decodable { let list: [T]; let pagination: Pagination }
    private struct Pagination: Decodable { let page: Int; let size: Int; let total: Int64 }
    static func page<T: Decodable, Item: Identifiable & Sendable>(
        _ bytes: Data, requestedPage: Int, size: Int, map: (T) throws -> Item
    ) throws -> NumberedPage<Item> {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(EnvelopeHeader.self, from: bytes) else {
            throw PageReadFailure.invalidResponse
        }
        guard header.code == 1000 else { throw PageReadFailure.businessCode(header.code) }
        guard let body = try? decoder.decode(Envelope<Body<T>>.self, from: bytes).data,
            requestedPage > 0, requestedPage < Int.max, (1...100).contains(size),
            body.pagination.page == requestedPage, body.pagination.size == size
        else { throw PageReadFailure.invalidResponse }
        let offset = Int64(requestedPage - 1).multipliedReportingOverflow(by: Int64(size))
        guard !offset.overflow, body.pagination.total >= offset.partialValue,
            Int64(body.list.count) == min(Int64(size), body.pagination.total - offset.partialValue)
        else { throw PageReadFailure.invalidResponse }
        let items: [Item]
        do { items = try body.list.map(map) } catch { throw PageReadFailure.invalidResponse }
        guard Set(items.map(\.id)).count == items.count else {
            throw PageReadFailure.invalidResponse
        }
        return NumberedPage(
            items: items, page: requestedPage, size: size, total: body.pagination.total)
    }
}
struct OwnedCouponDTO: Decodable {
    let id: Int64; let title: String; let description: String; let amount: Decimal
    let type: Int?; let status: Int?; let useStatus: Int?; let startTime: String?;
    let endTime: String?
    let condition: Condition?
    struct Condition: Decodable {
        let fullAmount: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                struct Value: Decodable { let fullAmount: Decimal }
                fullAmount = try JSONDecoder().decode(Value.self, from: Data(text.utf8)).fullAmount
            } else {
                enum Key: CodingKey { case fullAmount }
                fullAmount = try decoder.container(keyedBy: Key.self).decode(
                    Decimal.self, forKey: .fullAmount)
            }
        }
    }
    func value(availabilityContext: CouponAvailabilityContext = .owned) throws -> UserCoupon {
        guard id > 0, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !amount.isNaN, amount >= 0,
            condition.map({ !$0.fullAmount.isNaN && $0.fullAmount >= 0 }) ?? true
        else { throw PageReadFailure.invalidResponse }
        return UserCoupon(
            id: id, title: title, description: description, amountYuan: amount,
            minimumSpendYuan: condition?.fullAmount,
            startTime: startTime, endTime: endTime, type: type, status: status,
            useStatus: useStatus,
            availabilityContext: availabilityContext
        )
    }
}
