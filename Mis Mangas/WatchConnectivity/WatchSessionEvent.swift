//
//  WatchSessionEvent.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

/// What the connectivity session reports to the rest of the app, in the order it happens.
enum WatchSessionEvent {
    /// The session can send and receive; `isReachable` tells whether the other app is running.
    case activated(isReachable: Bool)
    case reachabilityChanged(isReachable: Bool)
    /// The iPhone published a new reading list.
    case readingSnapshot(ReadingSnapshot)
    /// The watch changed the volume being read of a manga.
    case readingUpdate(ReadingUpdate)
    /// The iPhone switched to another watch; the session activates again by itself.
    case deactivated
}
