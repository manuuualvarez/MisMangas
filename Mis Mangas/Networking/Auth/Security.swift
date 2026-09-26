//
//  Security.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// Production conformer of `SecurityData`: the Keychain as store and the uncached
/// `URLSession.authenticated`, so account data never lands in a disk cache.
struct Security: SecurityData {
    let store: any SecureStore

    var session: URLSession { .authenticated }

    nonisolated init(store: any SecureStore = SecKeyStore()) {
        self.store = store
    }
}
