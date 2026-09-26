//
//  ReadingItem.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// One manga of the reading list the iPhone sends to the watch: what the watch needs to show
/// the row and to edit the volume being read, nothing more.
struct ReadingItem: Codable, Hashable {
    let mangaID: Int
    let title: String
    let coverURL: String?
    let readingVolume: Int?
    let volumes: Int?
    let completeCollection: Bool
    let updatedAt: Date
}
