//
//  DisplayMode.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import Foundation

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

    /// The other layout, for a single button that switches between the two.
    var toggled: DisplayMode {
        switch self {
        case .list: .grid
        case .grid: .list
        }
    }

    /// The name of the mode, for a button that switches to it.
    var title: LocalizedStringResource {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }
}
