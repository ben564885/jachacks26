import Foundation
import Security

/// Bearer tokens live in the login keychain, keyed by developer id, so a token is never
/// written to disk in plaintext alongside the config file (§12).
enum Keychain {
    static let service = "com.synqit.notch"

    enum Failure: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
                return "Keychain error \(status): \(message)"
            }
        }
    }

    static func token(for devId: String) -> String? {
        var query = baseQuery(devId: devId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    /// Upsert: replaces any existing token for this developer.
    static func setToken(_ token: String, for devId: String) throws {
        let query = baseQuery(devId: devId)
        let data = Data(token.utf8)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw Failure.unexpectedStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Failure.unexpectedStatus(addStatus)
        }
    }

    @discardableResult
    static func deleteToken(for devId: String) throws -> Bool {
        let status = SecItemDelete(baseQuery(devId: devId) as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw Failure.unexpectedStatus(status)
    }

    private static func baseQuery(devId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: devId
        ]
    }
}
