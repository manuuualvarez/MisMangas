//
//  SyncError.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// Failures of a synchronization pass that the caller must act on. Every other failure of a
/// single operation is absorbed by the pass (retried, blocked or reported as rejected).
enum SyncError: LocalizedError {
    /// The server no longer accepts the session: the user has to sign in again. The queued
    /// operations that were not sent yet stay queued.
    case sessionExpired
    /// The local store could not be read or written.
    case persistence(PersistenceError)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            String(localized: "Your session expired. Please sign in again.")
        case .persistence(let error):
            error.errorDescription
        }
    }
}
