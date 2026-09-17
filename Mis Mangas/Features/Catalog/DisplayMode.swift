//
//  DisplayMode.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

/// How the catalog lays out its mangas. Stored as its raw value in user defaults.
enum DisplayMode: String {
    case list
    case grid

    /// SF Symbol of the mode, for the layout menu.
    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}
