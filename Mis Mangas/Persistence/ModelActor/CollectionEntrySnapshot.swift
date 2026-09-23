//
//  CollectionEntrySnapshot.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation

/// A collection entry as it leaves the store actor.
struct CollectionEntrySnapshot {
    let mangaID: Int
    let volumesOwned: [Int]
    let readingVolume: Int?
    let completeCollection: Bool
    let updatedAt: Date
}
