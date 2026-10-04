import Foundation
import Security

/// Reserved for future explicitly configured API adapters. Current sources need no secret.
public enum KeychainStore {
    private static let service = "com.jingteng.openai-usage-sentinel"
    public static func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw SentinelError.unavailable("Could not save API key to Keychain.") }; return
        }
        guard update == errSecSuccess else { throw SentinelError.unavailable("Could not update API key in Keychain.") }
    }
    public static func read(account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SentinelError.unavailable("Could not read API key from Keychain.") }
        return result as? Data
    }
}
