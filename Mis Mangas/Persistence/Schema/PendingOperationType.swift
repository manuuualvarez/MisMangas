//
//  PendingOperationType.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// Kind of a queued collection write. Stored as its raw value in `PendingOperation`.
enum PendingOperationType: String {
    case upsert
    case delete
}
