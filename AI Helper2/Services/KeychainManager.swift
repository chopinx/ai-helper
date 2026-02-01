import Foundation
import Security

/// Secure storage for sensitive data using iOS Keychain
class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.aihelper.api"

    private init() {}

    // MARK: - Public API

    /// Save API key for a provider
    func saveAPIKey(_ key: String, for provider: String) throws {
        let account = "apikey-\(provider)"

        // Delete existing key first
        try? deleteAPIKey(for: provider)

        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Use kSecAttrAccessibleAfterFirstUnlock for better persistence across app reinstalls
            // This allows access after first device unlock, more reliable in simulator
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve API key for a provider
    func getAPIKey(for provider: String) -> String? {
        let account = "apikey-\(provider)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Delete API key for a provider
    func deleteAPIKey(for provider: String) throws {
        let account = "apikey-\(provider)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if API key exists for a provider
    func hasAPIKey(for provider: String) -> Bool {
        return getAPIKey(for: provider) != nil
    }
}

// MARK: - Error Types

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode API key"
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        }
    }
}
