//
//  GenreDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

struct GenreDTO: Codable, Hashable, Identifiable {
    let id: UUID
    let genre: String
}
