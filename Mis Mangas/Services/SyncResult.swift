//
//  SyncResult.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

/// What one synchronization pass did.
struct SyncResult {
    /// Queued operations the server accepted (a delete of an entry it no longer had included).
    let applied: Int
    /// Operations that reached the retry limit during this pass and now wait for the user.
    let blocked: Int
    /// Manga ids whose queued operation the server refused; their queued change was discarded.
    let rejected: [Int]
    /// Entries written from the server snapshot.
    let upserted: Int
    /// Local entries removed because the server snapshot no longer has them.
    let removed: Int
}
