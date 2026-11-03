import Foundation
import MallCore

/// Read-only POST goods/comment/page, using the existing anonymous APIClient transport.
public final class HTTPProductReviewsService: ProductReviewsLoading, Sendable {
    private let environment: APIEnvironment
    private let transport: any ProductDetailTransport
    init(environment: APIEnvironment, transport: any ProductDetailTransport) {
        self.environment = environment; self.transport = transport
    }
    public convenience init(environment: APIEnvironment) {
        self.init(
            environment: environment,
            transport: URLSessionTransport(resourceTimeout: environment.resourceTimeout))
    }
    public func loadReviews(productID: Int64, page: Int, pageSize: Int) async throws
        -> ProductReviewPage
    {
        guard productID > 0 else { throw ProductDetailLoadFailure.invalidProductID }
        let base = environment.baseURL
        guard page > 0, pageSize > 0,
            base.scheme?.lowercased() == "https", base.host?.isEmpty == false,
            base.absoluteString.hasSuffix("/"), base.query == nil, base.fragment == nil,
            base.user == nil, base.password == nil,
            environment.requestTimeout > 0, environment.requestTimeout.isFinite,
            environment.resourceTimeout > 0, environment.resourceTimeout.isFinite,
            let url = URL(string: "goods/comment/page", relativeTo: base)?.absoluteURL
        else { throw ProductDetailLoadFailure.invalidConfiguration }
        struct Query: Encodable { let goodsId: String; let page: Int; let size: Int }
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: environment.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Query(goodsId: String(productID), page: page, size: pageSize))
        let data = try await APIClient.productBodyData(for: request, using: transport)
        return try ProductReviewsDecoder.page(
            data, productID: productID, requestedPage: page, pageSize: pageSize)
    }
}

enum ProductReviewsDecoder {
    private struct Body: Decodable { let list: [ProductReviewDTO]; let pagination: Pagination }
    private struct Pagination: Decodable { let total: Int64; let page: Int; let size: Int }
    static func page(_ data: Data, productID: Int64, requestedPage: Int, pageSize: Int) throws
        -> ProductReviewPage
    {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(EnvelopeHeader.self, from: data) else {
            throw ProductDetailLoadFailure.invalidResponse
        }
        guard header.code == 1000 else { throw ProductDetailLoadFailure.businessCode(header.code) }
        guard let envelope = try? decoder.decode(Envelope<Body>.self, from: data),
            let body = envelope.data,
            productID > 0, requestedPage > 0, pageSize > 0,
            body.pagination.page == requestedPage, body.pagination.size == pageSize,
            body.pagination.total >= 0, body.list.count <= pageSize
        else { throw ProductDetailLoadFailure.invalidResponse }
        let end = Int64(requestedPage).multipliedReportingOverflow(by: Int64(pageSize))
        guard !end.overflow, requestedPage < Int.max else {
            throw ProductDetailLoadFailure.invalidResponse
        }
        let next = end.partialValue < body.pagination.total ? requestedPage + 1 : nil
        return ProductReviewPage(
            items: try ProductReviewMapping.reviews(body.list, productID: productID), nextPage: next
        )
    }
}
