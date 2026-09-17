//
//  PageMetadataDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// `{ total, page, per }` envelope of every paginated response. `page` is 1-based.
struct PageMetadataDTO: Codable, Hashable {
    let total: Int
    let page: Int
    let per: Int
}
