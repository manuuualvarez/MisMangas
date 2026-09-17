//
//  AuthorDTO+Model.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// DTO → `Author`. The actor decides whether to insert or reuse by id.
extension AuthorDTO {
    func makeAuthor() -> Author {
        Author(id: id, firstName: firstName, lastName: lastName, role: role.rawValue)
    }

    func apply(to author: Author) {
        author.firstName = firstName
        author.lastName = lastName
        author.role = role.rawValue
    }
}
