//
//  UserCollectionEntry.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import SwiftData

/// The user's own record of a manga: volumes owned, the one being read, whether it is complete.
@Model
final class UserCollectionEntry {
    @Attribute(.unique) var id: UUID
    var mangaID: Int
    /// Ascending, without duplicates.
    var volumesOwned: [Int]
    var readingVolume: Int?
    var completeCollection: Bool
    var createdAt: Date
    var updatedAt: Date
    var manga: Manga?

    /// The highest volume number an entry keeps. The longest manga series in print run to about
    /// 200 volumes (Kochikame ended at 201), so 300 leaves room for any real collection, while a
    /// mistyped, pasted or corrupt count can no longer build millions of volume numbers that hang
    /// the app and then load with the collection, the widget and the upload payload on every
    /// launch.
    static let volumeLimit = 300

    init(
        id: UUID = UUID(),
        mangaID: Int,
        volumesOwned: [Int] = [],
        readingVolume: Int? = nil,
        completeCollection: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.mangaID = mangaID
        self.volumesOwned = volumesOwned
        self.readingVolume = readingVolume
        self.completeCollection = completeCollection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.manga = nil
    }
}
