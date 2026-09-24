//
//  CollectionFilter.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation

/// Which part of the collection the list shows.
enum CollectionFilter: CaseIterable {
    case all
    /// Series with a reading volume that are not complete yet.
    case reading
    case complete

    /// The name of the filter, for the options menu.
    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .reading: "Reading"
        case .complete: "Complete"
        }
    }
}

extension Array<Manga> {
    /// The mangas of the collection that match `filter`.
    func filtered(by filter: CollectionFilter) -> [Manga] {
        switch filter {
        case .all:
            self
        case .reading:
            self.filter { manga in
                guard let entry = manga.collectionEntry else { return false }
                return entry.readingVolume != nil && !entry.completeCollection
            }
        case .complete:
            self.filter { $0.collectionEntry?.completeCollection == true }
        }
    }

    /// What VoiceOver announces after `filter` is chosen: how many mangas it leaves on screen.
    func filterAnnouncement(for filter: CollectionFilter) -> String {
        let count = filtered(by: filter).count
        guard count > 0 else {
            return String(localized: "No mangas match")
        }
        // Grammar agreement ("1 manga" / "2 mangas") is only applied to attributed strings.
        return String(AttributedString(localized: "^[\(count) manga](inflect: true)").characters)
    }
}
