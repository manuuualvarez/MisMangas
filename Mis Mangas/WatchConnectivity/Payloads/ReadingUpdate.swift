//
//  ReadingUpdate.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// A change of the volume being read, made on the watch. `sentAt` is the moment of the change;
/// the iPhone applies it only when it is later than its own last change of that manga.
struct ReadingUpdate: Codable, Hashable {
    let mangaID: Int
    let readingVolume: Int
    let sentAt: Date
}
