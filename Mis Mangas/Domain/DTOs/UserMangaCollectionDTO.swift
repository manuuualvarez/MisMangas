//
//  UserMangaCollectionDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation

/// One entry of `GET /collection/manga`, with the full manga nested (OpenAPI).
struct UserMangaCollectionDTO: Codable {
    let id: UUID
    let manga: MangaDTO
    let volumesOwned: [Int]
    let readingVolume: Int?
    let completeCollection: Bool
}
