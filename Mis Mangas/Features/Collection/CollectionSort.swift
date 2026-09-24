//
//  CollectionSort.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation

/// The order of the collection list.
enum CollectionSort: CaseIterable {
    /// A to Z, the way the user reads titles (case and diacritics aside).
    case title
    /// Highest score first.
    case score
    /// The entry the user edited last first. Server refreshes stamp the manga, not the entry, so
    /// they never reorder the list.
    case recentlyUpdated

    /// The name of the order, for the options menu.
    var title: LocalizedStringResource {
        switch self {
        case .title: "Title"
        case .score: "Score"
        case .recentlyUpdated: "Recently updated"
        }
    }
}

extension Array<Manga> {
    /// The mangas of the collection in the order `sort` describes.
    func sorted(by sort: CollectionSort) -> [Manga] {
        switch sort {
        case .title:
            sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .score:
            sorted { $0.score > $1.score }
        case .recentlyUpdated:
            sorted { lhs, rhs in
                (lhs.collectionEntry?.updatedAt ?? .distantPast) > (rhs.collectionEntry?.updatedAt ?? .distantPast)
            }
        }
    }
}
