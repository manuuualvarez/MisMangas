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

    /// The volume being read, as the app writes it: "Vol. 7 of 42", or "Vol. 7" while the volume
    /// count is unknown.
    var volumeText: String {
        if let volumes {
            return String(localized: "Vol. \(readingVolume) of \(volumes)")
        }
        return String(localized: "Vol. \(readingVolume)")
    }

    /// The volume being read where there is little room: "7/42", or "7" while the volume count
    /// is unknown.
    var shortVolumeText: String {
        if let volumes {
            return String(localized: "\(readingVolume)/\(volumes)")
        }
        return readingVolume.formatted()
    }

    /// What VoiceOver reads for the manga: the title and the progress spelled out ("Dragon Ball,
    /// reading volume 7 of 42").
    var accessibilityLabel: String {
        if let volumes {
            return String(localized: "\(title), reading volume \(readingVolume) of \(volumes)")
        }
        return String(localized: "\(title), reading volume \(readingVolume)")
    }
}
