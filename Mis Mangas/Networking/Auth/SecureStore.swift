//
//  SecureStore.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// Key–value storage for session secrets. Production uses `SecKeyStore` (Keychain Services);
/// tests inject an in-memory conformer. Reading an absent key returns `nil` and deleting it does
/// not throw; any other failure surfaces as `AuthError.keychain(status)`.
protocol SecureStore: Sendable {
    func read(_ key: String) throws(AuthError) -> Data?
    func write(_ data: Data, key: String) throws(AuthError)
    func delete(_ key: String) throws(AuthError)
}
