//
//  Demographic.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// The 5 demographics served by `/list/demographics` plus `.unknown`.
/// DTOs carry the raw server string; resolve with `Demographic(rawValue:) ?? .unknown` at the mapping site.
/// Filter lists are fed from the live endpoint, never from `allCases`.
enum Demographic: String, CaseIterable {
    case seinen = "Seinen"
    case shounen = "Shounen"
    case shoujo = "Shoujo"
    case josei = "Josei"
    case kids = "Kids"
    case unknown = "Unknown"

    /// Taxonomy names are shown as the catalog spells them; only the fallback is localized.
    var displayName: String {
        self == .unknown ? String(localized: "Unknown") : rawValue
    }
}
