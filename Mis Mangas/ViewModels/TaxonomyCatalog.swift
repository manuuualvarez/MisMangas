//
//  TaxonomyCatalog.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

/// The three classification lists the backend serves, in server order. They feed every filter
/// and the advanced search form. An empty list is one that has not arrived yet.
struct TaxonomyCatalog {
    let genres: [String]
    let themes: [String]
    let demographics: [String]

    static let empty = TaxonomyCatalog(genres: [], themes: [], demographics: [])
}
