//
//  SyncStatus.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 25/09/2026.
//

import Foundation

/// What a screen shows about the collection's synchronization, read in one go: the queue of the
/// session's account, the last pass that reached the server and the refusals not yet shown.
struct SyncStatus {
    let pendingCount: Int
    let blockedCount: Int
    let lastSyncDate: Date?
    let lastResult: SyncResult?
    let rejections: [Int]
}
