//
//  AuthorDTO+Display.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

/// How a searched author is named on screen. The DTO stays a plain copy of the backend contract;
/// the derived name lives here, next to the other mappings.
extension AuthorDTO {
    /// "First Last", skipping empty name parts (studios often come with a single part).
    var displayName: String {
        [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
