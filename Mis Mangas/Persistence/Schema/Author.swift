//
//  Author.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import SwiftData

@Model
final class Author {
    @Attribute(.unique) var id: UUID
    var firstName: String
    var lastName: String
    /// Raw `AuthorRole` value as the API spells it ("Story & Art").
    var role: String
    var mangas: [Manga]

    init(id: UUID, firstName: String, lastName: String, role: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.mangas = []
    }
}

/// Presentation helpers of the stored model. Views read these instead of parsing raw fields.
extension Author {
    /// "First Last", skipping empty name parts (studios often come with a single part).
    var fullName: String {
        [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var roleValue: AuthorRole {
        AuthorRole(rawValue: role) ?? .none
    }
}
