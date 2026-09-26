//
//  SyncOutcome.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 25/09/2026.
//

import Foundation

/// Where the collection's queue stands after a sync the user asked for.
enum SyncOutcome: Equatable {
    case allSynced
    /// Changes that did not reach the server yet, such as without a connection.
    case waiting(Int)
    /// Changes the server kept failing, set aside until retried.
    case blocked(Int)
}

extension SyncOutcome {
    /// What VoiceOver says once a sync the user asked for is over.
    var announcement: AttributedString {
        switch self {
        case .allSynced:
            AttributedString(localized: "All changes synced")
        case .waiting(let count):
            AttributedString(localized: "^[\(count) change](inflect: true) still waiting to sync")
        case .blocked(let count):
            AttributedString(localized: "^[\(count) change](inflect: true) couldn't be synced")
        }
    }
}
