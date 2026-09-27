//
//  CollectionSyncPerformanceTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// Wall-clock budget of one synchronization pass of `MangaSyncService` over a large server
    /// collection: the real pipeline (fetch through `URLSessionMockInterface` → decode → map →
    /// persist by `MangaSyncActor`) on an in-memory store, timed with `ContinuousClock`.
    /// Oracles: the elapsed time against the budget, and what a fresh `ModelContext` reads
    /// afterwards compared with the entries the mock served (count, ids and one entry's values).
    @Suite("Collection sync — performance")
    struct CollectionSyncPerformanceTests {
        private static let token = "example.performance.token"

        private let container: ModelContainer
        private let service: MangaSyncService

        init() throws {
            CollectionMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            container = made.container
            let security = FakeSecurity(token: Self.token, email: SessionTestTokenFactory.email)
            service = CollectionTestSupport.makeService(actor: made.actor, account: CollectionTestSupport.account, security: security)
        }

        @Test(.timeLimit(.minutes(1)))
        func `Reconciling 500 remote entries on an empty store finishes under 3 seconds`() async throws {
            let remote = Self.remoteEntries(count: 500)
            try Self.serve(remote)

            let duration = try await ContinuousClock().measure {
                _ = try await service.synchronizeCollection()
            }

            #expect(duration < .seconds(3))
            if duration > .seconds(1) {
                Issue.record(
                    "Reconciling 500 entries took \(Self.describe(duration)): over the 1 s watermark, within the 3 s budget",
                    severity: .warning
                )
            }
            try Self.expectStore(container, toHold: remote)
        }

        @Test(.timeLimit(.minutes(1)))
        func `Reconciling 50 remote entries on an empty store finishes under 1 second`() async throws {
            let remote = Self.remoteEntries(count: 50)
            try Self.serve(remote)

            let duration = try await ContinuousClock().measure {
                _ = try await service.synchronizeCollection()
            }

            #expect(duration < .seconds(1))
            try Self.expectStore(container, toHold: remote)
        }

        // MARK: - Remote collection

        /// Ids of the served mangas start here: far from the ids of every committed fixture.
        private static let firstMangaID = 1001

        /// Authors are shared across mangas (one in every `authorsPerCycle` entries), so the pass
        /// also exercises the dedupe of `Author` rows.
        private static let authorsPerCycle = 25

        /// Fixed taxonomies every served manga carries, like real entries do.
        private static let genres = [GenreDTO(id: UUID(), genre: "Action"), GenreDTO(id: UUID(), genre: "Drama")]
        private static let themes = [ThemeDTO(id: UUID(), theme: "Psychological")]
        private static let demographics = [DemographicDTO(id: UUID(), demographic: "Seinen")]

        /// `count` entries with distinct manga ids and varied user fields: `volumesOwned` grows
        /// with the ordinal, `readingVolume` is set on every other entry, and every third entry is
        /// complete.
        private static func remoteEntries(count: Int) -> [UserMangaCollectionDTO] {
            let authors = (0 ..< authorsPerCycle).map { index in
                AuthorDTO(id: UUID(), firstName: "Author", lastName: "Number \(index)", role: .storyAndArt)
            }
            return (0 ..< count).map { ordinal in
                let mangaID = firstMangaID + ordinal
                let volumes = ordinal % 20 + 1
                return UserMangaCollectionDTO(
                    id: UUID(),
                    manga: manga(id: mangaID, volumes: volumes, author: authors[ordinal % authorsPerCycle]),
                    volumesOwned: Array(1 ... (ordinal % volumes + 1)),
                    readingVolume: ordinal.isMultiple(of: 2) ? ordinal % volumes + 1 : nil,
                    completeCollection: ordinal.isMultiple(of: 3)
                )
            }
        }

        private static func manga(id: Int, volumes: Int, author: AuthorDTO) -> MangaDTO {
            MangaDTO(
                id: id,
                title: "Manga \(id)",
                titleEnglish: "Manga \(id) (EN)",
                titleJapanese: "マンガ \(id)",
                synopsis: "Synopsis of manga \(id), long enough to resemble a real one from the catalog.",
                background: nil,
                startDate: Date(timeIntervalSinceReferenceDate: 700_000_000),
                endDate: nil,
                score: Double(id % 100) / 10,
                status: .publishing,
                chapters: volumes * 8,
                volumes: volumes,
                mainPicture: "https://cdn.myanimelist.net/images/manga/1/\(id)l.jpg",
                url: "https://myanimelist.net/manga/\(id)",
                authors: [author],
                genres: genres,
                themes: themes,
                demographics: demographics
            )
        }

        /// Routes `GET /collection/manga` to the bytes of `entries`, encoded with the app encoder.
        private static func serve(_ entries: [UserMangaCollectionDTO]) throws {
            try CollectionMockScenario.set(.collectionList, .data(JSONEncoder.app.encode(entries)))
        }

        // MARK: - Oracle

        /// The store, read through a fresh context, holds exactly `remote`: one entry per served
        /// manga id and nothing else, with the user fields of one middle entry as served. The
        /// pass touched the wire once, for the collection only.
        private static func expectStore(_ container: ModelContainer, toHold remote: [UserMangaCollectionDTO]) throws {
            #expect(CollectionMockScenario.hits(.collectionList) == 1)
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try CollectionTestSupport.entries(in: context)
            #expect(entries.count == remote.count)
            #expect(Set(entries.map(\.mangaID)) == Set(remote.map(\.manga.id)))

            let sample = try #require(remote.dropFirst(remote.count / 2).first)
            let stored = try #require(try CollectionTestSupport.entry(mangaID: sample.manga.id, in: context))
            #expect(stored.volumesOwned == sample.volumesOwned)
            #expect(stored.readingVolume == sample.readingVolume)
            #expect(stored.completeCollection == sample.completeCollection)
        }

        private static func describe(_ duration: Duration) -> String {
            duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated))
        }
    }
}
