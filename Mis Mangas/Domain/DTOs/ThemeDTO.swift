//
//  ThemeDTO.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

struct ThemeDTO: Codable, Hashable, Identifiable {
    let id: UUID
    let theme: String
}
