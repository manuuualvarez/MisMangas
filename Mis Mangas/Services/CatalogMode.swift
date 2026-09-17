//
//  CatalogMode.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Which server list the catalog shows. `modeKey` is the value stored in `CatalogEntry`.
enum CatalogMode: Hashable {
    case all
    case best

    var modeKey: String {
        switch self {
        case .all: "all"
        case .best: "best"
        }
    }

    var title: String {
        switch self {
        case .all: String(localized: "Catalog")
        case .best: String(localized: "Best rated")
        }
    }
}
