//
//  SecKeyStore.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
import Security

/// `SecureStore` over Keychain Services: generic passwords scoped by `service`, one account per
/// key, readable after the first unlock and never migrated to another device.
struct SecKeyStore: SecureStore {
    let service: String

    init(service: String = "cloud.manuelalvarez.Mis-Mangas.auth") {
        self.service = service
    }

    func read(_ key: String) throws(AuthError) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw .keychain(status)
        }
    }

    /// Adds the item, or updates it when it already exists.
    func write(_ data: Data, key: String) throws(AuthError) {
        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw .keychain(updateStatus)
            }
        default:
            throw .keychain(status)
        }
    }

    func delete(_ key: String) throws(AuthError) {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .keychain(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
