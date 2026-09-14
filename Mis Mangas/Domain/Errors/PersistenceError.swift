//
//  PersistenceError.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Failures of the local store. `LocalizedError` so views can show `errorDescription` directly.
enum PersistenceError: LocalizedError {
    case notFound
    /// A write, including the reads it needs, could not be committed; carries the store error.
    case saveFailed(any Error)
    /// The `ModelContainer` could not be created or opened.
    case containerUnavailable(any Error)

    var errorDescription: String? {
        switch self {
        case .notFound:
            String(localized: "The item was not found in your library.")
        case .saveFailed(let error):
            String(localized: "Your changes could not be saved: \(error.localizedDescription)")
        case .containerUnavailable(let error):
            String(localized: "The local library could not be opened: \(error.localizedDescription)")
        }
    }
}
