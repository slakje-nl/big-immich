//
//  KeychainHelper.swift
//  KeychainHelper
//
//  Created by Maciej Płoński on 06/01/2026.
//

import Foundation
import Security

public enum ImmichAPIAuthMethod: String, CaseIterable, Identifiable {
    case apiKey
    case emailAndPassword

    public var id: String {
        rawValue
    }
}

public class KeychainHelper {
    /// Process-lifetime credential store used by UI tests. The unsigned test
    /// build has no keychain-access-group entitlement, so keychain writes are
    /// unreliable there; when this is enabled, credentials round-trip through
    /// memory instead. Never enabled during normal use.
    private static var inMemoryStore: [String: String]?

    public static func enableInMemoryStore() {
        if inMemoryStore == nil {
            inMemoryStore = [:]
        }
    }

    public static func saveImmichAPIAuthMethod(method: ImmichAPIAuthMethod)
        -> Bool
    {
        save(method.rawValue, forKey: "immichAPIAuthMethod")
    }

    public static func loadImmichAPIAuthMethod() -> ImmichAPIAuthMethod? {
        if let method = load(forKey: "immichAPIAuthMethod") {
            ImmichAPIAuthMethod(rawValue: method)
        } else {
            nil
        }
    }

    public static func saveImmichURL(url: String) -> Bool {
        save(url, forKey: "immichURL")
    }

    public static func loadImmichURL() -> String? {
        let value = load(forKey: "immichURL")

        if value == "" {
            return nil
        }
        return value
    }

    public static func saveImmichAuthEmail(email: String) -> Bool {
        save(email, forKey: "immichAuthEmail")
    }

    public static func loadImmichAuthEmail() -> String? {
        let value = load(forKey: "immichAuthEmail")

        if value == "" {
            return nil
        }
        return value
    }

    public static func saveImmichAuthPassword(password: String) -> Bool {
        save(password, forKey: "immichAuthPassword")
    }

    public static func loadImmichAuthPassword() -> String? {
        let value = load(forKey: "immichAuthPassword")

        if value == "" {
            return nil
        }
        return value
    }

    public static func saveImmichAPIKey(key: String) -> Bool {
        save(key, forKey: "immichAuthAPIKey")
    }

    public static func loadImmichAPIKey() -> String? {
        let value = load(forKey: "immichAuthAPIKey")

        if value == "" {
            return nil
        }
        return value
    }

    static func save(_ value: String, forKey key: String) -> Bool {
        if inMemoryStore != nil {
            inMemoryStore?[key] = value
            return true
        }

        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item if present
        delete(forKey: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrAccessGroup as String: "3U4PH469WK.nl.slakje.BigImmich"
        ]

        if SecItemAdd(query as CFDictionary, nil) == errSecSuccess {
            return true
        }

        // Fall back without the shared access group. Needed for unsigned
        // builds (e.g. UI tests) where the keychain-access-group entitlement
        // isn't applied; load() already falls back to the no-group item.
        query.removeValue(forKey: kSecAttrAccessGroup as String)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(forKey key: String, withAccessGroup: Bool = true)
        -> String?
    {
        if let inMemoryStore {
            return inMemoryStore[key]
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if withAccessGroup {
            query[kSecAttrAccessGroup as String] =
                "3U4PH469WK.nl.slakje.BigImmich"
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8)
        {
            return value
        }

        // temporary migration to a keychain with access group
        if withAccessGroup, let oldValue = load(forKey: key, withAccessGroup: false) {
            if save(oldValue, forKey: key) {
                return oldValue
            }
        }

        return nil
    }

    static func delete(forKey key: String) {
        if inMemoryStore != nil {
            inMemoryStore?.removeValue(forKey: key)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
