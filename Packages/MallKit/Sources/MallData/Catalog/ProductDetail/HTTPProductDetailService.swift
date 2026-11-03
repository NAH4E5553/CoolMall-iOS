import Foundation
import MallCore

/// GET page/goodsDetail and read-only POST goods/spec/list. Anonymous reads
/// have no automatic retry, credentials or page/selection state.
public final class HTTPProductDetailService: ProductDetailLoading, Sendable {
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

    public func loadDetail(productID: Int64) async throws -> ProductDetailSnapshot {
        let request = try request(productID: productID, specifications: false)
        let data = try await APIClient.productBodyData(for: request, using: transport)
        return try ProductDetailDecoder.detail(data, productID: productID)
    }

    public func loadSpecifications(productID: Int64) async throws -> [ProductSpecification] {
        let request = try request(productID: productID, specifications: true)
        let data = try await APIClient.productBodyData(for: request, using: transport)
        return try ProductDetailDecoder.specifications(data, productID: productID)
    }

    private func request(productID: Int64, specifications: Bool) throws -> URLRequest {
        guard productID > 0 else { throw ProductDetailLoadFailure.invalidProductID }
        let base = environment.baseURL
        guard base.scheme?.lowercased() == "https", base.host?.isEmpty == false,
            base.absoluteString.hasSuffix("/"), base.query == nil, base.fragment == nil,
            base.user == nil, base.password == nil,
            environment.requestTimeout > 0, environment.requestTimeout.isFinite,
            environment.resourceTimeout > 0, environment.resourceTimeout.isFinite,
            let endpoint = URL(
                string: specifications ? "goods/spec/list" : "page/goodsDetail",
                relativeTo: base)?.absoluteURL,
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else { throw ProductDetailLoadFailure.invalidConfiguration }
        if !specifications {
            components.queryItems = [URLQueryItem(name: "goodsId", value: String(productID))]
        }
        guard let url = components.url else { throw ProductDetailLoadFailure.invalidConfiguration }
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: environment.requestTimeout)
        request.httpMethod = specifications ? "POST" : "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if specifications {
            struct SpecificationRequest: Encodable { let goodsId: Int64 }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(SpecificationRequest(goodsId: productID))
        }
        return request
    }
}
