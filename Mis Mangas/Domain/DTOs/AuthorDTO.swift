//
//  AuthorDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

struct AuthorDTO: Codable, Hashable, Identifiable {
    let id: UUID
    let firstName: String
    let lastName: String
    let role: AuthorRole
}
