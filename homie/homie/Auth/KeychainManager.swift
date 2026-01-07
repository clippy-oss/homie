//
//  KeychainManager.swift
//  homie
//
//  Secure token storage using macOS Keychain
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    private let service = "com.homie.app"
    
    private init() {}
    
    enum KeychainKey: String {
        // Note: Auth tokens (accessToken, refreshToken, userId) are now managed by Supabase SDK
        // Only OAuth credentials for external services remain here
        case linearCredentials = "oauth_linear_credentials"
        case googleCalendarCredentials = "oauth_google_calendar_credentials"
    }
    
    /// Save a value to the Keychain
    func save(_ value: String, for key: KeychainKey) -> Bool {
        guard let data = value.data(using: .utf8) else {
            Logger.error("❌ KeychainManager: Failed to convert value to data", module: "Auth")
            return false
        }

        // Delete existing item if present
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            Logger.info("✅ KeychainManager: Saved \(key.rawValue)", module: "Auth")
            return true
        } else {
            Logger.error("❌ KeychainManager: Failed to save \(key.rawValue), status: \(status)", module: "Auth")
            return false
        }
    }
    
    /// Retrieve a value from the Keychain
    func get(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                Logger.error("⚠️ KeychainManager: Failed to retrieve \(key.rawValue), status: \(status)", module: "Auth")
            }
            return nil
        }

        return string
    }
    
    /// Delete a value from the Keychain
    @discardableResult
    func delete(_ key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Clear all stored credentials
    func clearAll() {
        Logger.info("🗑️ KeychainManager: Clearing all credentials", module: "Auth")
        // Note: Auth tokens are now managed by Supabase SDK
        delete(.linearCredentials)
        delete(.googleCalendarCredentials)
    }

    // MARK: - Generic Codable Support

    /// Save a Codable value to the Keychain
    func save<T: Encodable>(_ value: T, for key: KeychainKey) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else {
            Logger.error("❌ KeychainManager: Failed to encode value for \(key.rawValue)", module: "Auth")
            return false
        }

        // Delete existing item if present
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            Logger.info("✅ KeychainManager: Saved \(key.rawValue)", module: "Auth")
            return true
        } else {
            Logger.error("❌ KeychainManager: Failed to save \(key.rawValue), status: \(status)", module: "Auth")
            return false
        }
    }

    /// Retrieve a Codable value from the Keychain
    func get<T: Decodable>(_ key: KeychainKey) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            if status != errSecItemNotFound {
                Logger.error("⚠️ KeychainManager: Failed to retrieve \(key.rawValue), status: \(status)", module: "Auth")
            }
            return nil
        }

        let decoder = JSONDecoder()
        guard let value = try? decoder.decode(T.self, from: data) else {
            Logger.error("❌ KeychainManager: Failed to decode value for \(key.rawValue)", module: "Auth")
            return nil
        }

        return value
    }
}

