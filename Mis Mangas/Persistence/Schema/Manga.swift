//
//  Manga.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import SwiftData

/// A manga as the app stores it. The catalog, the detail screen, the collection, the Watch and
/// the widget all read this one type; only `MangaSyncActor` writes it.
@Model
final class Manga {
    @Attribute(.unique) var id: Int
    var title: String
    var titleEnglish: String?
    var titleJapanese: String?
    var synopsis: String?
    var background: String?
    /// Raw `MangaStatus` value; an unknown value from the server is stored as "none".
    var status: String
    var score: Double
    var startDate: Date?
    var endDate: Date?
    var chapters: Int?
    var volumes: Int?
    var mainPictureURL: String?
    var url: String?
    var genres: [String]
    var themes: [String]
    var demographics: [String]
    /// Last time the full record arrived from the server; `nil` until then.
    var cachedAt: Date?
    /// Mirrors `collectionEntry != nil`, so predicates and widget fetches can filter on it.
    var inCollection: Bool
    var updatedAt: Date

    @Relationship(inverse: \Author.mangas)
    var authors: [Author]
    /// Index rows pointing at this manga; deleting the manga deletes them.
    @Relationship(deleteRule: .cascade, inverse: \CatalogEntry.manga)
    var catalogEntries: [CatalogEntry]
    @Relationship(deleteRule: .cascade, inverse: \UserCollectionEntry.manga)
    var collectionEntry: UserCollectionEntry?

    init(
        id: Int,
        title: String,
        titleEnglish: String? = nil,
        titleJapanese: String? = nil,
        synopsis: String? = nil,
        background: String? = nil,
        status: String,
        score: Double,
        startDate: Date? = nil,
        endDate: Date? = nil,
        chapters: Int? = nil,
        volumes: Int? = nil,
        mainPictureURL: String? = nil,
        url: String? = nil,
        genres: [String] = [],
        themes: [String] = [],
        demographics: [String] = [],
        cachedAt: Date? = nil,
        inCollection: Bool = false,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.titleEnglish = titleEnglish
        self.titleJapanese = titleJapanese
        self.synopsis = synopsis
        self.background = background
        self.status = status
        self.score = score
        self.startDate = startDate
        self.endDate = endDate
        self.chapters = chapters
        self.volumes = volumes
        self.mainPictureURL = mainPictureURL
        self.url = url
        self.genres = genres
        self.themes = themes
        self.demographics = demographics
        self.cachedAt = cachedAt
        self.inCollection = inCollection
        self.updatedAt = updatedAt
        self.authors = []
        self.catalogEntries = []
        self.collectionEntry = nil
    }
}

/// Presentation helpers of the stored model. Views read these instead of parsing raw fields.
extension Manga {
    var statusValue: MangaStatus {
        MangaStatus(rawValue: status) ?? .none
    }

    var coverURL: URL? {
        mainPictureURL.flatMap(URL.init(string:))
    }

    /// Full name of the first author; `nil` without authors.
    var primaryAuthorName: String? {
        authors.first?.fullName
    }

    /// Whether any classification list (demographics, genres, themes) has content.
    var hasTags: Bool {
        !(demographics.isEmpty && genres.isEmpty && themes.isEmpty)
    }

    /// The score with two decimals in the user's locale.
    var formattedScore: String {
        score.formatted(.number.precision(.fractionLength(2)))
    }

    /// The publication line in words ("Finished, 1994 to 2001", "Publishing, since 1989", or the
    /// status alone without dates), so VoiceOver does not depend on how it reads "·" and "–".
    var publicationAccessibilityLabel: String {
        let status = statusValue.displayName
        guard let start = startDate?.formatted(.dateTime.year()) else {
            return status
        }
        if let end = endDate?.formatted(.dateTime.year()) {
            return String(localized: "\(status), \(start) to \(end)")
        }
        return String(localized: "\(status), since \(start)")
    }

    /// What VoiceOver reads for a catalog row or cell: title, first author (when there is one)
    /// and score.
    var catalogAccessibilityLabel: String {
        if let author = primaryAuthorName {
            String(localized: "\(title), by \(author), score \(formattedScore)")
        } else {
            String(localized: "\(title), score \(formattedScore)")
        }
    }
}
