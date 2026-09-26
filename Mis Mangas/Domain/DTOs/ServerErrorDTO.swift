//
//  ServerErrorDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

/// Body of every error response of the backend: `{"error": true, "reason": "<text>"}`.
/// `reason` is interpreted only where a specific text has a meaning of its own and is never
/// shown to the user as-is.
struct ServerErrorDTO: Codable {
    let error: Bool
    let reason: String
}
