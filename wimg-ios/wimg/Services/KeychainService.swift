import Foundation
import Security

/// Minimal Keychain wrapper for secure credential storage.
/// Replaces UserDefaults for sensitive data (sync key, API keys, FinTS credentials).
enum KeychainService {
    private static let service = "com.wimg"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ account: String, value: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Migrate a value from UserDefaults to Keychain (one-time, on app update).
    static func migrateFromUserDefaults(udKey: String, account: String) {
        if get(account) == nil,
           let value = UserDefaults.standard.string(forKey: udKey)
        {
            set(account, value: value)
            UserDefaults.standard.removeObject(forKey: udKey)
        }
    }

    /// Delete all wimg Keychain items (used on data reset).
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Account Keys

    static let syncKey = "sync_key"
    static let fintsBLZ = "fints_blz"
    static let fintsKennung = "fints_kennung"
    static let fintsPIN = "fints_pin"
    static let fintsTanMedium = "fints_tan_medium"

    /// Whether the user has opted in to storing their FinTS PIN.
    static var hasSavedPIN: Bool {
        return Self.get(fintsPIN) != nil
    }

    /// Whether full quick-refresh credentials are available (BLZ + kennung + PIN).
    static var hasFintsCredentials: Bool {
        return Self.get(fintsBLZ) != nil && Self.get(fintsKennung) != nil && Self.get(fintsPIN) != nil
    }

    /// Clear all FinTS credentials (PIN, TAN medium — keeps BLZ + kennung for prefill).
    static func clearFintsPIN() {
        delete(fintsPIN)
    }
}
