//
//  UserMangaCollectionRequest.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

/// Body of `POST /collection/manga`: the manga id and the user's own fields (OpenAPI).
struct UserMangaCollectionRequest: Codable, Hashable {
    let manga: Int
    let completeCollection: Bool
    let volumesOwned: [Int]
    let readingVolume: Int?
}
