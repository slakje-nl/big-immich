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

    public var id: String { rawValue }
}

public class KeychainHelper {
    static public func saveImmichAPIAuthMethod(method: ImmichAPIAuthMethod)
        -> Bool
    {
        return save(method.rawValue, forKey: "immichAPIAuthMethod")
    }

    static public func loadImmichAPIAuthMethod() -> ImmichAPIAuthMethod? {
        if let method = load(forKey: "immichAPIAuthMethod") {
            return ImmichAPIAuthMethod(rawValue: method)
        } else {
            return nil
        }
    }

    static public func saveImmichURL(url: String) -> Bool {
        return save(url, forKey: "immichURL")
    }

    static public func loadImmichURL() -> String? {
        let value = load(forKey: "immichURL")

        if value == "" {
            return nil
        }
        return value
    }

    static public func saveImmichAuthEmail(email: String) -> Bool {
        return save(email, forKey: "immichAuthEmail")
    }

    static public func loadImmichAuthEmail() -> String? {
        let value = load(forKey: "immichAuthEmail")

        if value == "" {
            return nil
        }
        return value
    }

    static public func saveImmichAuthPassword(password: String) -> Bool {
        return save(password, forKey: "immichAuthPassword")
    }

    static public func loadImmichAuthPassword() -> String? {
        let value = load(forKey: "immichAuthPassword")

        if value == "" {
            return nil
        }
        return value
    }

    static public func saveImmichAPIKey(key: String) -> Bool {
        return save(key, forKey: "immichAuthAPIKey")
    }

    static public func loadImmichAPIKey() -> String? {
        let value = load(forKey: "immichAuthAPIKey")

        if value == "" {
            return nil
        }
        return value
    }

    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item if present
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrAccessGroup as String: "3U4PH469WK.nl.slakje.BigImmich",
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(forKey key: String, withAccessGroup: Bool = true)
        -> String?
    {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
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
        if withAccessGroup, let oldValue = self.load(forKey: key, withAccessGroup: false) {
            if save(oldValue, forKey: key) {
                return oldValue
            }
        }

        return nil
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
