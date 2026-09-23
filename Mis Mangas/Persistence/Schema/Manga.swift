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
    /// Author ids in the order the server lists them; the relationship does not keep an order.
    /// The default lets a store written before this attribute existed migrate in place.
    var authorOrder: [UUID] = []
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

    /// The authors in the order the server lists them. Any author missing from `authorOrder`
    /// (a record stored before the order was kept) follows, by full name, so the order never
    /// depends on how the store returns the relationship.
    var orderedAuthors: [Author] {
        let positions = Dictionary(authorOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return authors.sorted { lhs, rhs in
            switch (positions[lhs.id], positions[rhs.id]) {
            case let (left?, right?):
                left < right
            case (.some, nil):
                true
            case (nil, .some):
                false
            case (nil, nil):
                lhs.fullName < rhs.fullName
            }
        }
    }

    /// Full name of the author the server lists first; `nil` without authors.
    var primaryAuthorName: String? {
        orderedAuthors.first?.fullName
    }

    /// Whether any classification list (demographics, genres, themes) has content.
    var hasTags: Bool {
        !(demographics.isEmpty && genres.isEmpty && themes.isEmpty)
    }

    /// The Japanese title tagged as Japanese, so the text is typeset with Japanese rules and
    /// assistive technologies speak it in Japanese instead of in the app's language.
    var attributedJapaneseTitle: AttributedString? {
        guard let titleJapanese else {
            return nil
        }
        var attributed = AttributedString(titleJapanese)
        attributed.languageIdentifier = "ja"
        return attributed
    }

    /// Whether anyone has rated the manga. The server sends 0 for an unrated one: an average of
    /// user votes from 1 to 10 can never be 0, so 0 is the absence of a score, not a grade.
    var isScored: Bool {
        score > 0
    }

    /// The score with two decimals in the user's locale, or a dash when nobody has rated it.
    var formattedScore: String {
        isScored ? score.formatted(.number.precision(.fractionLength(2))) : "—"
    }

    /// What VoiceOver reads for the score on its own: the grade, or that there is none.
    var scoreAccessibilityLabel: String {
        isScored ? String(localized: "Score \(formattedScore)") : String(localized: "No score")
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
    /// and score, or that it has none.
    var catalogAccessibilityLabel: String {
        switch (primaryAuthorName, isScored) {
        case let (author?, true):
            String(localized: "\(title), by \(author), score \(formattedScore)")
        case let (author?, false):
            String(localized: "\(title), by \(author), no score")
        case (nil, true):
            String(localized: "\(title), score \(formattedScore)")
        case (nil, false):
            String(localized: "\(title), no score")
        }
    }
}
