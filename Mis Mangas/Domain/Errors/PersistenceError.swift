//
//  PersistenceError.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Failures of the local store. `LocalizedError` so views can show `errorDescription` directly.
/// The message is fixed: the store error it carries can name the container path, tables and
/// constraints, which are not for the user's eyes; it stays attached for the debugger.
enum PersistenceError: LocalizedError {
    case notFound
    /// A write, including the reads it needs, could not be committed; carries the store error.
    case saveFailed(any Error)
    /// The `ModelContainer` could not be created or opened.
    case containerUnavailable(any Error)
    /// The calling task was cancelled before the write started; the store was left untouched.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notFound:
            String(localized: "The item was not found in your library.")
        case .saveFailed:
            String(localized: "Your changes could not be saved.")
        case .containerUnavailable:
            String(localized: "The local library could not be opened.")
        case .cancelled:
            String(localized: "The change was cancelled before it was saved.")
        }
    }
}
