//
//  PendingOperationSnapshot.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation

/// A queued collection write as it leaves the store actor.
struct PendingOperationSnapshot {
    let id: UUID
    let type: PendingOperationType
    let mangaID: Int
    let payload: Data?
    let attempts: Int
}
