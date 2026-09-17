//
//  PageDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// Paginated response `{ metadata, items }`. `Item: Sendable` is required: without it the compiler
/// rejects returning a page from `@APIActor` ("Non-Sendable 'MangaPageDTO'").
struct PageDTO<Item: Codable & Hashable & Sendable>: Codable, Hashable {
    let metadata: PageMetadataDTO
    let items: [Item]
}

typealias MangaPageDTO = PageDTO<MangaDTO>
typealias AuthorPageDTO = PageDTO<AuthorDTO>
