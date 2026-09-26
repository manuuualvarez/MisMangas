//
//  UserResponse.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// Response of `GET /users/jwt/me`: the account the session token belongs to (OpenAPI).
struct UserResponse: Codable {
    let id: UUID
    let email: String
    let role: String
    let isActive: Bool
    let isAdmin: Bool
}
