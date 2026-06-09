import Foundation
import Security

protocol KeychainStoring {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) throws -> String?
    func remove(_ key: String) throws
}

/// macOS Keychain wrapper for user-specific secrets (the per-user Foundry JWT).
///
/// Mirrors the iOS `KeychainService` but uses a **distinct Mac service name**
/// (`co.gitwork.foundry`) — the Mac app does not share the iPhone app's Keychain
/// access group. Only user-scoped tokens are stored here; never a server secret.
final class KeychainStore: KeychainStoring {
    static let defaultService = "co.gitwork.foundry"
    private let service: String

    init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    func set(_ value: String, for key: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.persistence("Unable to store secure item (\(status)).")
        }
    }

    func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AppError.persistence("Unable to read secure item (\(status)).")
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.persistence("Unable to remove secure item (\(status)).")
        }
    }
}
