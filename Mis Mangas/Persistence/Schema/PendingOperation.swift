//
//  PendingOperation.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import SwiftData

/// A collection write that could not reach the server yet. Replayed in FIFO order; blocked
/// after repeated failures until the user intervenes.
@Model
final class PendingOperation {
    @Attribute(.unique) var id: UUID
    /// Raw `PendingOperationType` value.
    var operationType: String
    var mangaID: Int
    /// Encoded request body for an upsert; `nil` for a delete.
    var payload: Data?
    var createdAt: Date
    var attempts: Int
    var lastError: String?
    var blockedAt: Date?

    init(operationType: PendingOperationType, mangaID: Int, payload: Data? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.operationType = operationType.rawValue
        self.mangaID = mangaID
        self.payload = payload
        self.createdAt = createdAt
        self.attempts = 0
        self.lastError = nil
        self.blockedAt = nil
    }
}
