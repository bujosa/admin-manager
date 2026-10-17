import Foundation
import Security

/// Stores and retrieves device passwords securely in the macOS Keychain.
enum KeychainHelper {

    private static let service = "com.bujosa.adminmanager"

    // MARK: - Save

    static func save(password: String, for device: Device) {
        guard let data = password.data(using: .utf8) else { return }
        let account = accountKey(for: device)

        // Delete any existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new entry
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainHelper] Failed to save password: OSStatus \(status)")
        }
    }

    // MARK: - Retrieve

    static func getPassword(for device: Device) -> String? {
        let account = accountKey(for: device)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    static func deletePassword(for device: Device) {
        let account = accountKey(for: device)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private

    private static func accountKey(for device: Device) -> String {
        "\(device.username)@\(device.hostname):\(device.port)"
    }
}
