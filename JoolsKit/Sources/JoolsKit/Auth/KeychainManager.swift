import Foundation
import Security

/// Errors that can occur during keychain operations
public enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case updateFailed(OSStatus)
    case unexpectedData

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from keychain (status: \(status))"
        case .updateFailed(let status):
            return "Failed to update keychain (status: \(status))"
        case .unexpectedData:
            return "Unexpected data format in keychain"
        }
    }
}

/// Manages secure storage of sensitive data in the iOS Keychain
public final class KeychainManager: Sendable {
    // MARK: - Constants

    private let service: String
    private let apiKeyAccount = "api-key"

    // MARK: - Initialization

    public init(service: String = "com.jools.app") {
        self.service = service
    }

    // MARK: - API Key Management

    /// Save the API key to the keychain
    public func saveAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Load the API key from the keychain
    public func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
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

    /// Delete the API key from the keychain
    public func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if an API key exists in the keychain
    public func hasAPIKey() -> Bool {
        loadAPIKey() != nil
    }

    /// Update the API key in the keychain
    public func updateAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, save it instead
            try saveAPIKey(key)
        } else if status != errSecSuccess {
            throw KeychainError.updateFailed(status)
        }
    }
}
