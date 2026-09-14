//
//  CatalogEntry.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import SwiftData

/// One position of a server-paginated list. `(modeKey, ordinal)` reproduces the server order
/// of a catalog mode ("all", "best", and the filter and search modes), so a query filtered by
/// `modeKey` and sorted by `ordinal` shows exactly what the server sent, page after page.
@Model
final class CatalogEntry {
    var modeKey: String
    /// Absolute position in the mode: `(page - 1) * per + index`.
    var ordinal: Int
    /// When this page was fetched; the purge removes entries older than the retention window.
    var fetchedAt: Date
    var manga: Manga?

    init(modeKey: String, ordinal: Int, fetchedAt: Date) {
        self.modeKey = modeKey
        self.ordinal = ordinal
        self.fetchedAt = fetchedAt
        self.manga = nil
    }
}
