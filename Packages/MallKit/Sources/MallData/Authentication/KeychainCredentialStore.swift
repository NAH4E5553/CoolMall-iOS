import Foundation
import MallCore
import Security

struct AccountCredentialRecord: Codable, Sendable {
    let tokens: AuthenticationTokens
    let profile: AccountProfile
}

/// Synchronous operations run in SessionCoordinator's isolation. No await between
/// validating a generation, committing credentials and publishing the new identity.
protocol AccountCredentialStoring: Sendable {
    func read() throws -> AccountCredentialRecord?
    func save(_ value: AccountCredentialRecord) throws
    func delete() throws
}

struct KeychainCredentialStore: AccountCredentialStoring {
    let service: String
    private var key: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "current-session-v1",
        ]
    }
    func read() throws -> AccountCredentialRecord? {
        var query = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
            let record = try? JSONDecoder().decode(AccountCredentialRecord.self, from: data),
            record.profile.id > 0, !record.tokens.token.isEmpty,
            !record.tokens.refreshToken.isEmpty
        else { throw AccountFailure.credentialRead }
        return record
    }
    func save(_ value: AccountCredentialRecord) throws {
        guard let data = try? JSONEncoder().encode(value) else {
            throw AccountFailure.credentialWrite
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            NSLog("Account Keychain update failed (OSStatus %d)", status)
            throw AccountFailure.credentialWrite
        }
        let inserted = SecItemAdd(key.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard inserted == errSecSuccess else {
            NSLog("Account Keychain insert failed (OSStatus %d)", inserted)
            throw AccountFailure.credentialWrite
        }
    }
    func delete() throws {
        let status = SecItemDelete(key as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountFailure.credentialDelete
        }
    }
}
