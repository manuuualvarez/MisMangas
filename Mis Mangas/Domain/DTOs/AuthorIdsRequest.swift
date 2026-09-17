//
//  AuthorIdsRequest.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// Body of `POST /list/authorsByIds`: the author UUIDs as strings (OpenAPI).
struct AuthorIdsRequest: Codable, Hashable {
    let ids: [String]
}
