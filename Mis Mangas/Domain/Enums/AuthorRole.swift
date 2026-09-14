//
//  AuthorRole.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Author credit as the API spells it. Unknown values fall back to `.none`.
enum AuthorRole: String, Codable {
    case art = "Art"
    case story = "Story"
    case storyAndArt = "Story & Art"
    case none = "None"

    /// Unknown server values decode as `.none` instead of failing the whole `MangaDTO`.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .none
    }

    var displayName: String {
        switch self {
        case .art: String(localized: "Art")
        case .story: String(localized: "Story")
        case .storyAndArt: String(localized: "Story & Art")
        case .none: String(localized: "Unknown")
        }
    }
}
