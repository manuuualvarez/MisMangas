//
//  SyncEvent.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 25/09/2026.
//

/// Something a synchronization pass ended with that the app must act on, whoever asked for it.
enum SyncEvent {
    /// The server no longer accepts the session.
    case sessionExpired
    /// A pass ended, whatever its outcome: what the queue holds and what the last pass did may have
    /// changed.
    case passFinished
}
