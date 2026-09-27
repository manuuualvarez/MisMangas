//
//  CustomSearch.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// Body of `POST /search/manga`. Nil fields are omitted from the JSON; `searchContains` is always sent.
struct CustomSearch: Codable, Hashable {
    let searchTitle: String?
    let searchAuthorFirstName: String?
    let searchAuthorLastName: String?
    let searchGenres: [String]?
    let searchThemes: [String]?
    let searchDemographics: [String]?
    let searchContains: Bool
}
