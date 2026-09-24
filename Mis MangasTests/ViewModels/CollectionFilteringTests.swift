//
//  CollectionFilteringTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// What the collection screen shows over the stored collection: which mangas each filter keeps,
/// the order of each sort, and the summary numbers. The collection is written through the actor
/// and read back from a fresh context, as the screen's query reads it. Oracles: the sample
/// collection written out by hand (ids, titles, scores, volumes owned, reading volume, complete
/// flag) and the dates each scenario stamps.
@Suite("Collection filtering, sorting and stats")
struct CollectionFilteringTests {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Dr. Slump: in the sample catalog but not in the sample collection. Added as owned, not
    /// being read and not complete, the one state the sample collection lacks.
    private static let drSlumpID = 796

    // MARK: - Filter

    @Test(arguments: [
        (CollectionFilter.all, [1, 2, 13, 21, 26, 42, 656, 796, 33327]),
        (CollectionFilter.reading, [2, 13, 26, 42, 656]),
        (CollectionFilter.complete, [1, 21, 33327]),
    ])
    func `Filtering keeps only the mangas in the chosen state`(filter: CollectionFilter, expectedIDs: [Int]) async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await Self.seedSampleCollection(actor)
        let drSlump = try Self.sampleManga(id: Self.drSlumpID)
        try await actor.upsertCollectionEntry(from: UserMangaCollectionDTO(
            id: UUID(), manga: drSlump, volumesOwned: [1, 2, 3], readingVolume: nil, completeCollection: false
        ))
        let context = PersistenceTestSupport.freshContext(container)
        let collection = try Self.collection(in: context)

        let filtered = collection.filtered(by: filter)

        #expect(filtered.map(\.id).sorted() == expectedIDs)
    }

    // MARK: - Sort

    @Test(arguments: [
        // Berserk, Death Note, Dragon Ball, Hunter x Hunter, Monster, One Piece, Tokyo Ghoul, Vagabond.
        (CollectionSort.title, [2, 21, 42, 26, 1, 13, 33327, 656]),
        // 9.47, 9.24, 9.22, 9.15, 8.73, 8.7, 8.52, 8.41.
        (CollectionSort.score, [2, 656, 13, 1, 26, 21, 33327, 42]),
    ])
    func `Sorting the sample collection puts titles A to Z and scores highest first`(sort: CollectionSort, expectedIDs: [Int]) async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await Self.seedSampleCollection(actor)
        let context = PersistenceTestSupport.freshContext(container)
        let collection = try Self.collection(in: context)

        let sorted = collection.sorted(by: sort)

        #expect(sorted.map(\.id) == expectedIDs)
    }

    @Test func `Sorting by title ignores case the way the user reads it`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let titles = [1: "Monster", 2: "Berserk", 13: "akira"]
        for (id, title) in titles {
            let manga = try Self.retitled(Self.sampleManga(id: id), title)
            try await actor.upsertCollectionEntry(from: UserMangaCollectionDTO(
                id: UUID(), manga: manga, volumesOwned: [1], readingVolume: 1, completeCollection: false
            ))
        }
        let context = PersistenceTestSupport.freshContext(container)
        let collection = try Self.collection(in: context)

        let sorted = collection.sorted(by: .title)

        // A plain code-point comparison would put "akira" after every capitalized title.
        #expect(sorted.map(\.title) == ["akira", "Berserk", "Monster"])
    }

    @Test func `Recently updated follows the last edit of the user and not the last server refresh`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        // The user edits the entries in this order, oldest first.
        let editOrder = [42, 2, 26, 13]
        for (offset, id) in editOrder.enumerated() {
            try await actor.upsertCollectionEntry(from: Self.sampleEntry(id: id), now: Self.t0.addingTimeInterval(TimeInterval(offset)))
        }
        // Later the server refreshes the same mangas in the opposite order, which stamps the manga
        // and leaves the entry alone.
        for (offset, id) in editOrder.reversed().enumerated() {
            _ = try await actor.cacheDetail(Self.sampleManga(id: id), now: Self.t0.addingTimeInterval(TimeInterval(100 + offset)))
        }
        let context = PersistenceTestSupport.freshContext(container)
        let collection = try Self.collection(in: context)
        let byServerRefresh = collection.sorted { $0.updatedAt > $1.updatedAt }.map(\.id)
        try #require(byServerRefresh == [42, 2, 26, 13], "The scenario needs the two clocks to disagree")

        let sorted = collection.sorted(by: .recentlyUpdated)

        #expect(sorted.map(\.id) == [13, 26, 2, 42])
    }

    // MARK: - Stats

    @Test func `Stats of the sample collection count 8 series and 165 volumes with 38 percent complete`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await Self.seedSampleCollection(actor)
        let context = PersistenceTestSupport.freshContext(container)
        let collection = try Self.collection(in: context)

        let stats = CollectionStats(mangas: collection)

        #expect(stats.total == 8)
        // 10 + 60 + 20 + 30 + 18 + 12 + 14 + 1.
        #expect(stats.volumesOwned == 165)
        // 3 complete out of 8.
        let percent = stats.completeRatio.formatted(
            .percent.precision(.fractionLength(0)).locale(Locale(identifier: "en_US"))
        )
        #expect(percent == "38%")
    }

    @Test func `Stats of an empty collection are all zero and never NaN`() {
        let stats = CollectionStats(mangas: [])

        #expect(stats.total == 0)
        #expect(stats.volumesOwned == 0)
        #expect(stats.completeRatio == 0)
    }

    // MARK: - Helpers

    /// Stores every entry of the sample collection as the server would return it.
    private static func seedSampleCollection(_ actor: MangaSyncActor) async throws {
        for entry in SampleData.collection {
            try await actor.upsertCollectionEntry(from: entry)
        }
    }

    /// The stored collection, by id so the input order never matches an expected order by chance.
    private static func collection(in context: ModelContext) throws -> [Manga] {
        let descriptor = FetchDescriptor<Manga>(
            predicate: #Predicate { $0.inCollection == true },
            sortBy: [SortDescriptor(\.id)]
        )
        return try context.fetch(descriptor)
    }

    private static func sampleManga(id: Int) throws -> MangaDTO {
        try #require(SampleData.mangas.first { $0.id == id }, "Manga \(id) is not in the sample")
    }

    private static func sampleEntry(id: Int) throws -> UserMangaCollectionDTO {
        try #require(SampleData.collection.first { $0.manga.id == id }, "Manga \(id) is not in the sample collection")
    }

    /// The same manga under another title.
    private static func retitled(_ dto: MangaDTO, _ title: String) -> MangaDTO {
        MangaDTO(
            id: dto.id,
            title: title,
            titleEnglish: dto.titleEnglish,
            titleJapanese: dto.titleJapanese,
            synopsis: dto.synopsis,
            background: dto.background,
            startDate: dto.startDate,
            endDate: dto.endDate,
            score: dto.score,
            status: dto.status,
            chapters: dto.chapters,
            volumes: dto.volumes,
            mainPicture: dto.mainPicture,
            url: dto.url,
            authors: dto.authors,
            genres: dto.genres,
            themes: dto.themes,
            demographics: dto.demographics
        )
    }
}
