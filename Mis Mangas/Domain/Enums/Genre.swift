//
//  Genre.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// The 21 genres served by `/list/genres` (raw values are the exact API spelling) plus `.unknown`.
/// DTOs carry the raw server string; resolve with `Genre(rawValue:) ?? .unknown` at the mapping site.
/// Filter lists are fed from the live endpoint, never from `allCases`.
enum Genre: String, CaseIterable {
    case action = "Action"
    case adventure = "Adventure"
    case awardWinning = "Award Winning"
    case drama = "Drama"
    case fantasy = "Fantasy"
    case horror = "Horror"
    case supernatural = "Supernatural"
    case mystery = "Mystery"
    case sliceOfLife = "Slice of Life"
    case comedy = "Comedy"
    case sciFi = "Sci-Fi"
    case suspense = "Suspense"
    case sports = "Sports"
    case ecchi = "Ecchi"
    case romance = "Romance"
    case girlsLove = "Girls Love"
    case boysLove = "Boys Love"
    case gourmet = "Gourmet"
    case erotica = "Erotica"
    case hentai = "Hentai"
    case avantGarde = "Avant Garde"
    case unknown = "Unknown"

    /// Taxonomy names are shown as the catalog spells them; only the fallback is localized.
    var displayName: String {
        self == .unknown ? String(localized: "Unknown") : rawValue
    }
}
