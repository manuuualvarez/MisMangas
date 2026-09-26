//
//  ReadingWidgetItem.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// One manga of the reading widget: what a row needs to show where the reader is, nothing more.
struct ReadingWidgetItem: Identifiable, Hashable {
    /// The manga's id.
    let id: Int
    let title: String
    /// The cached cover, when the app has written it.
    let coverFileURL: URL?
    let readingVolume: Int
    let volumes: Int?
}

extension ReadingWidgetItem {
    /// How far into the manga the reader is, from 0 to 1; `nil` while the volume count is unknown.
    var progress: Double? {
        guard let volumes, volumes > 0 else {
            return nil
        }
        return Double(readingVolume) / Double(volumes)
    }

    /// The link that opens the manga's detail in the app.
    var deepLink: URL {
        MangaDeepLink(mangaID: id).url
    }
}
