import Foundation

/// Editable values, never a second store of committed server addresses.
public struct ShippingAddressInput: Equatable, Sendable {
    public var contact: String
    public var phone: String
    public var province: String
    public var city: String
    public var district: String
    public var address: String
    public var isDefault: Bool
    public init(
        contact: String = "", phone: String = "", province: String = "", city: String = "",
        district: String = "", address: String = "", isDefault: Bool = false
    ) {
        self.contact = contact; self.phone = phone; self.province = province; self.city = city
        self.district = district; self.address = address; self.isDefault = isDefault
    }
    public var normalized: Self {
        func trim(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Self(
            contact: trim(contact), phone: trim(phone), province: trim(province), city: trim(city),
            district: trim(district), address: trim(address), isDefault: isDefault)
    }
    public var isValid: Bool {
        let value = normalized
        return !value.contact.isEmpty
            && value.phone.range(of: "^1[3-9][0-9]{9}$", options: .regularExpression) != nil
            && !value.province.isEmpty && !value.city.isEmpty && !value.district.isEmpty
            && !value.address.isEmpty
    }
}
public struct ShippingAddress: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let value: ShippingAddressInput
    public init(id: Int64, value: ShippingAddressInput) { self.id = id; self.value = value }
}
public protocol AddressLoading: Sendable {
    func loadAddresses(accountID: Int64, page: Int, pageSize: Int) async throws -> NumberedPage<
        ShippingAddress
    >
    func loadAddress(accountID: Int64, id: Int64) async throws -> ShippingAddress
}
public protocol AddressWriting: Sendable {
    func saveAddress(accountID: Int64, id: Int64?, input: ShippingAddressInput) async throws
    func deleteAddress(accountID: Int64, id: Int64) async throws
}
public enum AddressWriteFailure: Error, Equatable, Sendable {
    case authenticationRequired, invalidConfiguration, invalidInput, busy, unconfirmed
    case rejected(code: Int, message: String?)
}
public struct AddressRegion: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let children: [Self]
    public init(id: String, name: String, children: [Self] = []) {
        self.id = id; self.name = name; self.children = children
    }
}
public protocol AddressRegionsLoading: Sendable {
    func loadRegions() async throws -> [AddressRegion]
}
