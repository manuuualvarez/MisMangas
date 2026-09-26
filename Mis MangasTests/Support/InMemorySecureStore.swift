//
//  InMemorySecureStore.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Synchronization

/// `SecureStore` backed by a dictionary, so session tests never touch the simulator Keychain.
///
/// Besides the protocol surface it offers what a test needs as an oracle and as a setup tool:
/// `storedString(_:)` / `storedKeys` read the dictionary directly (never through the code under
/// test), `seed(_:key:)` preloads a value, and `failNextWrite(with:key:)` /
/// `failNextDelete(with:key:)` make the next write or delete (optionally only to one key) throw
/// `AuthError.keychain(status)` without changing anything, the way Keychain Services reports a
/// failed `SecItemAdd` or `SecItemDelete`. The two failures are independent: arming one never
/// consumes or replaces the other.
///
/// A `final class` because `Mutex` is not copyable: a struct holding one could not be used as
/// `any SecureStore`.
final class InMemorySecureStore: SecureStore {
    private struct PendingFailure {
        /// `nil` fails the next operation whatever its key.
        let key: String?
        let status: OSStatus

        func matches(_ candidate: String) -> Bool {
            key == nil || key == candidate
        }
    }

    private struct State {
        var values: [String: Data] = [:]
        var pendingWriteFailure: PendingFailure?
        var pendingDeleteFailure: PendingFailure?
    }

    private let state = Mutex(State())

    init() {}

    // MARK: - SecureStore

    func read(_ key: String) throws(AuthError) -> Data? {
        state.withLock { $0.values[key] }
    }

    func write(_ data: Data, key: String) throws(AuthError) {
        let failure = state.withLock { state -> OSStatus? in
            if let pending = state.pendingWriteFailure, pending.matches(key) {
                state.pendingWriteFailure = nil
                return pending.status
            }
            state.values[key] = data
            return nil
        }
        if let failure {
            throw .keychain(failure)
        }
    }

    func delete(_ key: String) throws(AuthError) {
        let failure = state.withLock { state -> OSStatus? in
            if let pending = state.pendingDeleteFailure, pending.matches(key) {
                state.pendingDeleteFailure = nil
                return pending.status
            }
            state.values.removeValue(forKey: key)
            return nil
        }
        if let failure {
            throw .keychain(failure)
        }
    }

    // MARK: - Test controls

    /// Stores `value` as UTF-8 without going through `write`, so a pending failure is not consumed.
    func seed(_ value: String, key: String) {
        state.withLock { $0.values[key] = Data(value.utf8) }
    }

    /// The next `write` (to `key`, or to any key when `nil`) throws `AuthError.keychain(status)`
    /// and stores nothing. Later writes succeed again.
    func failNextWrite(with status: OSStatus, key: String? = nil) {
        state.withLock { $0.pendingWriteFailure = PendingFailure(key: key, status: status) }
    }

    /// The next `delete` (of `key`, or of any key when `nil`) throws `AuthError.keychain(status)`
    /// and removes nothing. Later deletes succeed again.
    func failNextDelete(with status: OSStatus, key: String? = nil) {
        state.withLock { $0.pendingDeleteFailure = PendingFailure(key: key, status: status) }
    }

    // MARK: - Oracle

    /// The raw value under `key` decoded as UTF-8, read straight from the dictionary.
    func storedString(_ key: String) -> String? {
        state.withLock { state in
            state.values[key].flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    /// Every key currently stored.
    var storedKeys: Set<String> {
        state.withLock { Set($0.values.keys) }
    }
}
