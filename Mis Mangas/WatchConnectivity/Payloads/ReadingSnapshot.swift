//
//  ReadingSnapshot.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// The whole reading list as the iPhone sees it, most recently updated first. The watch replaces
/// its local list with the last snapshot it receives.
struct ReadingSnapshot: Codable, Hashable {
    let generatedAt: Date
    let items: [ReadingItem]
}
