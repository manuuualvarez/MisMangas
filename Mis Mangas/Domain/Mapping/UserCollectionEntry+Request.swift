//
//  UserCollectionEntry+Request.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

/// Stored entry → body of `POST /collection/manga`.
extension UserCollectionEntry {
    /// The request that sends this entry to the server; the manga travels as its id.
    func toRequest() -> UserMangaCollectionRequest {
        UserMangaCollectionRequest(
            manga: mangaID,
            completeCollection: completeCollection,
            volumesOwned: volumesOwned,
            readingVolume: readingVolume
        )
    }
}
