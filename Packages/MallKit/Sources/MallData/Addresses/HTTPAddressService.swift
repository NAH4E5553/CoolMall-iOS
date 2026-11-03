import Foundation
import MallCore

/// One App-owned adapter. A write is dispatched once, with no retry or optimistic commit.
public actor HTTPAddressService: AddressLoading, AddressWriting {
    private let environment: APIEnvironment
    private let session: any AccountReadAuthorizing
    private let transport: any ProductDetailTransport
    private var writers: Set<Int64> = []
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
    public func loadAddresses(accountID: Int64, page: Int, pageSize: Int) async throws
        -> NumberedPage<ShippingAddress>
    {
        guard page > 0, (1...100).contains(pageSize) else {
            throw PageReadFailure.invalidConfiguration
        }
        struct Query: Encodable { let page: Int; let size: Int; let sort = "desc" }
        return try await read(
            accountID: accountID, path: "page",
            body: JSONEncoder().encode(Query(page: page, size: pageSize))
        ) { bytes in
            try CouponPageDecoder.page(bytes, requestedPage: page, size: pageSize) {
                (dto: AddressDTO) in try dto.value()
            }
        }
    }
    public func loadAddress(accountID: Int64, id: Int64) async throws -> ShippingAddress {
        guard id > 0 else { throw PageReadFailure.invalidConfiguration }
        return try await read(accountID: accountID, path: "info?id=\(id)", body: nil) { bytes in
            guard let header = try? JSONDecoder().decode(EnvelopeHeader.self, from: bytes) else {
                throw PageReadFailure.invalidResponse
            }
            guard header.code == 1000 else { throw PageReadFailure.businessCode(header.code) }
            guard let dto = try? JSONDecoder().decode(Envelope<AddressDTO>.self, from: bytes).data,
                dto.id == id
            else { throw PageReadFailure.invalidResponse }
            return try dto.value()
        }
    }
    private func read<Value: Sendable>(
        accountID: Int64, path: String, body: Data?, decode: (Data) throws -> Value
    ) async throws -> Value {
        guard accountID > 0 else { throw PageReadFailure.authenticationRequired }
        var request = try CouponHTTP.request(environment, path: "user/address/" + path)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        let context = try await session.authorization(
            accountID: accountID, environmentURL: environment.baseURL)
        try Task.checkCancellation()
        request.setValue(context.token, forHTTPHeaderField: "Authorization")
        do {
            let bytes = try await CouponHTTP.body(request, transport: transport)
            let value = try decode(bytes)
            try await session.validateAuthorization(context)
            try Task.checkCancellation()
            return value
        } catch {
            try await session.validateAuthorization(context)
            throw error
        }
    }
    public func saveAddress(accountID: Int64, id: Int64?, input: ShippingAddressInput) async throws
    {
        let value = input.normalized
        guard value.isValid, id.map({ $0 > 0 }) ?? true else {
            throw AddressWriteFailure.invalidInput
        }
        try await write(
            accountID: accountID, path: id == nil ? "add" : "update",
            body: JSONEncoder().encode(WriteDTO(id: id, value: value)))
    }
    public func deleteAddress(accountID: Int64, id: Int64) async throws {
        guard id > 0 else { throw AddressWriteFailure.invalidInput }
        struct Command: Encodable { let ids: [Int64] }
        try await write(
            accountID: accountID, path: "delete", body: JSONEncoder().encode(Command(ids: [id])))
    }
    private func write(accountID: Int64, path: String, body: Data) async throws {
        try Task.checkCancellation()
        guard accountID > 0 else { throw AddressWriteFailure.authenticationRequired }
        let context: AccountReadContext
        var request: URLRequest
        do {
            request = try CouponHTTP.request(environment, path: "user/address/" + path)
            context = try await session.authorization(
                accountID: accountID, environmentURL: environment.baseURL)
        } catch is CancellationError { throw CancellationError() } catch PageReadFailure
            .authenticationRequired
        { throw AddressWriteFailure.authenticationRequired } catch {
            throw AddressWriteFailure.invalidConfiguration
        }
        try Task.checkCancellation()
        guard writers.insert(accountID).inserted else { throw AddressWriteFailure.busy }
        defer { writers.remove(accountID) }
        request.httpBody = body;
        request.setValue(context.token, forHTTPHeaderField: "Authorization")
        do {
            let bytes = try await CouponHTTP.body(request, transport: transport)
            guard let header = try? JSONDecoder().decode(EnvelopeHeader.self, from: bytes) else {
                throw AddressWriteFailure.unconfirmed
            }
            struct Message: Decodable { let message: String? }
            let text = (try? JSONDecoder().decode(Message.self, from: bytes))?.message?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard header.code == 1000 else {
                throw AddressWriteFailure.rejected(
                    code: header.code, message: text?.isEmpty == false ? text : nil)
            }
            // Android consumes a code-only acknowledgment for add/update/delete.
            // No returned ID is used; a subsequent list read supplies committed facts.
            try await session.validateAuthorization(context)
            try Task.checkCancellation()
        } catch {
            try await session.validateAuthorization(context)
            if error is CancellationError { throw CancellationError() }
            if let failure = error as? AddressWriteFailure { throw failure }
            if error as? PageReadFailure == .authenticationRequired {
                throw AddressWriteFailure.authenticationRequired
            }
            throw AddressWriteFailure.unconfirmed
        }
    }
}
struct AddressDTO: Decodable {
    let id: Int64
    let contact: String; let phone: String; let province: String; let city: String
    let district: String; let address: String; let isDefault: Bool
    func value() throws -> ShippingAddress {
        let input = ShippingAddressInput(
            contact: contact, phone: phone, province: province, city: city, district: district,
            address: address, isDefault: isDefault)
        // Historical server addresses remain displayable even if current input rules differ.
        guard id > 0, !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PageReadFailure.invalidResponse
        }
        return ShippingAddress(id: id, value: input)
    }
}
private struct WriteDTO: Encodable {
    let id: Int64?
    let contact: String; let phone: String; let province: String; let city: String
    let district: String; let address: String; let isDefault: Bool
    init(id: Int64?, value: ShippingAddressInput) {
        self.id = id; contact = value.contact; phone = value.phone; province = value.province
        city = value.city; district = value.district; address = value.address;
        isDefault = value.isDefault
    }
}
