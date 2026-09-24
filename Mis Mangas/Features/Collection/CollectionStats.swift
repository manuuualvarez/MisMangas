//
//  CollectionStats.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

/// The summary of the collection: how many series, how many volumes owned, and the share of
/// series that are complete.
struct CollectionStats {
    let total: Int
    let volumesOwned: Int
    /// Between 0 and 1; 0 for an empty collection.
    let completeRatio: Double

    init(mangas: [Manga]) {
        let entries = mangas.compactMap(\.collectionEntry)
        total = mangas.count
        volumesOwned = entries.reduce(0) { $0 + $1.volumesOwned.count }
        let completeCount = entries.count { $0.completeCollection }
        completeRatio = total == 0 ? 0 : Double(completeCount) / Double(total)
    }
}
