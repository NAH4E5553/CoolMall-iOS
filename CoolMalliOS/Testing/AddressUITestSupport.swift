#if DEBUG
    import Foundation
    import MallCore

    /// Opt-in in-memory server fixture; never reads/writes production addresses.
    actor AddressUITestSupport: AddressLoading, AddressWriting {
        private let scenario: String
        private var values: [ShippingAddress]
        private var writes = 0
        static func make(arguments: [String]) -> AddressUITestSupport? {
            guard let index = arguments.firstIndex(of: "--ui-addresses"),
                arguments.indices.contains(index + 1)
            else { return nil }
            return AddressUITestSupport(scenario: arguments[index + 1])
        }
        init(scenario: String) {
            self.scenario = scenario
            values =
                scenario == "empty"
                ? []
                : (1...12).map { index in
                    ShippingAddress(
                        id: Int64(index),
                        value: ShippingAddressInput(
                            contact: "联系人\(index)", phone: "13800000000", province: "北京市",
                            city: "北京市", district: index == 1 ? "东城区" : "海淀区",
                            address: "测试街道\(index)号", isDefault: index == 1))
                }
        }
        func loadAddresses(accountID: Int64, page: Int, pageSize: Int) async throws -> NumberedPage<
            ShippingAddress
        > {
            guard accountID == 920001 else { throw PageReadFailure.authenticationRequired }
            let items = values.dropFirst((page - 1) * pageSize).prefix(pageSize)
            return NumberedPage(
                items: Array(items), page: page, size: pageSize, total: Int64(values.count))
        }
        func loadAddress(accountID: Int64, id: Int64) async throws -> ShippingAddress {
            guard accountID == 920001, let value = values.first(where: { $0.id == id }) else {
                throw PageReadFailure.invalidResponse
            }
            return value
        }
        func saveAddress(accountID: Int64, id: Int64?, input: ShippingAddressInput) async throws {
            guard accountID == 920001 else { throw AddressWriteFailure.authenticationRequired }
            writes += 1
            if scenario == "rejection" && writes == 1 {
                throw AddressWriteFailure.rejected(code: 500, message: "地址保存失败")
            }
            if scenario == "unknown" { throw AddressWriteFailure.unconfirmed }
            if scenario == "pending" { try await Task.sleep(for: .seconds(100)) }
            try Task.checkCancellation()
            let value = ShippingAddress(id: id ?? (values.map(\.id).max() ?? 0) + 1, value: input)
            if let index = values.firstIndex(where: { $0.id == id }) {
                values[index] = value
            } else {
                values.insert(value, at: 0)
            }
        }
        func deleteAddress(accountID: Int64, id: Int64) async throws {
            guard accountID == 920001 else { throw AddressWriteFailure.authenticationRequired }
            values.removeAll { $0.id == id }
        }
    }
#endif
