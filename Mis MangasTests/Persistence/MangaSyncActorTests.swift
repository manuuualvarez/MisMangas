//
//  MangaSyncActorTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// The single write point of the store, exercised with the real page fixtures. Every test owns
/// an in-memory container, so the suite runs in parallel. Oracles: the ids, order and author
/// ids of the fixtures, and what a fresh `ModelContext` reads after each call.
@Suite("MangaSyncActor")
struct MangaSyncActorTests {
    private static let day: TimeInterval = 86400
    private static let sevenDays = 7 * day
    private static let eightDaysAgo = Date.now.addingTimeInterval(-8 * day)
    private static let threeDaysAgo = Date.now.addingTimeInterval(-3 * day)

    /// First 20 items of `/list/mangas`: ids 1…4 and 7…22, 20 distinct authors.
    private let allPage1: [MangaDTO]
    /// First 20 items of `/list/bestMangas`: shares ids 1, 2, 3 and 13 with `allPage1`.
    private let bestPage1: [MangaDTO]

    init() throws {
        allPage1 = try PersistenceTestSupport.pageItems("mangas_page.json")
        bestPage1 = try PersistenceTestSupport.pageItems("mangas_page_best.json")
    }

    /// A second page of `all`: the same 20 mangas with ids shifted out of the fixture range,
    /// because the real fixtures do not contain 20 ids unseen by page 1.
    private var allPage2: [MangaDTO] {
        allPage1.shiftingIDs(by: 1000)
    }

    /// Ids present in both fixtures, computed from the fixtures themselves.
    private var sharedIDs: Set<Int> {
        Set(allPage1.map(\.id)).intersection(bestPage1.map(\.id))
    }

    // MARK: - Page 1

    @Test func `Page 1 of all stores 20 mangas, their authors and 20 index entries in server order`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)

        let context = PersistenceTestSupport.freshContext(container)
        let mangas = try PersistenceTestSupport.mangasByID(in: context)
        #expect(mangas.map(\.id) == allPage1.map(\.id).sorted())
        #expect(mangas.allSatisfy { $0.cachedAt != nil })
        #expect(mangas.allSatisfy { !$0.inCollection })
        #expect(try PersistenceTestSupport.fetchAll(Author.self, in: context).count == PersistenceTestSupport.distinctAuthorCount(in: allPage1))

        let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
        #expect(entries.map(\.ordinal) == Array(0 ..< 20))
        #expect(entries.compactMap(\.manga?.id) == allPage1.map(\.id))
    }

    @Test func `Upsert links each manga to its authors`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)

        let context = PersistenceTestSupport.freshContext(container)
        let monster = try #require(try PersistenceTestSupport.manga(id: 1, in: context))
        #expect(monster.authors.map(\.lastName) == ["Urasawa"])
        #expect(monster.authors.first?.role == "Story & Art")
        #expect(monster.genres == ["Award Winning", "Drama", "Mystery"])
        #expect(monster.status == "finished")
    }

    @Test func `Upsert stamps cachedAt with the date it is given`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1, now: Self.eightDaysAgo)

        let context = PersistenceTestSupport.freshContext(container)
        let mangas = try PersistenceTestSupport.mangasByID(in: context)
        #expect(mangas.allSatisfy { $0.cachedAt == Self.eightDaysAgo })
        let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
        #expect(entries.allSatisfy { $0.fetchedAt == Self.eightDaysAgo })
    }

    // MARK: - Page 2

    @Test func `Page 2 appends ordinals 20 to 39 and leaves 40 mangas`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "all", page: 2, per: 20, dtos: allPage2)

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.mangasByID(in: context).count == 40)
        // Page 2 carries the same authors as page 1: no new Author rows.
        #expect(try PersistenceTestSupport.fetchAll(Author.self, in: context).count == PersistenceTestSupport.distinctAuthorCount(in: allPage1))

        let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
        #expect(entries.map(\.ordinal) == Array(0 ..< 40))
        #expect(entries.compactMap(\.manga?.id) == allPage1.map(\.id) + allPage2.map(\.id))
    }

    @Test func `Loading page 2 twice does not duplicate entries or mangas`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "all", page: 2, per: 20, dtos: allPage2)
        try await actor.replaceCatalogPage(modeKey: "all", page: 2, per: 20, dtos: allPage2)

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.mangasByID(in: context).count == 40)
        let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
        #expect(entries.count == 40)
        #expect(entries.map(\.ordinal) == Array(0 ..< 40))
    }

    @Test func `Reloading page 1 replaces the whole mode but keeps the cached mangas`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "all", page: 2, per: 20, dtos: allPage2)
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
        #expect(entries.map(\.ordinal) == Array(0 ..< 20))
        #expect(entries.compactMap(\.manga?.id) == allPage1.map(\.id))
        // The index is replaced; the detail cache only shrinks through the purge.
        #expect(try PersistenceTestSupport.mangasByID(in: context).count == 40)
    }

    @Test func `An empty page 1 empties the mode index`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: [])

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).isEmpty)
    }

    // MARK: - Modes

    @Test func `Best mode keeps the all index intact and shares repeated mangas`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "best", page: 1, per: 20, dtos: bestPage1)

        let context = PersistenceTestSupport.freshContext(container)
        let all = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
        #expect(all.map(\.ordinal) == Array(0 ..< 20))
        #expect(all.compactMap(\.manga?.id) == allPage1.map(\.id))

        let best = try PersistenceTestSupport.catalogEntries(modeKey: "best", in: context)
        #expect(best.map(\.ordinal) == Array(0 ..< 20))
        #expect(best.compactMap(\.manga?.id) == bestPage1.map(\.id))

        let expectedIDs = Set(allPage1.map(\.id)).union(bestPage1.map(\.id))
        #expect(!sharedIDs.isEmpty)
        #expect(try PersistenceTestSupport.mangasByID(in: context).map(\.id) == expectedIDs.sorted())
        #expect(try PersistenceTestSupport.fetchAll(Author.self, in: context).count == PersistenceTestSupport.distinctAuthorCount(in: allPage1 + bestPage1))
    }

    @Test func `A manga listed in both modes is indexed twice and stored once`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let berserkID = 2
        #expect(sharedIDs.contains(berserkID))

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "best", page: 1, per: 20, dtos: bestPage1)

        let context = PersistenceTestSupport.freshContext(container)
        let berserk = try #require(try PersistenceTestSupport.manga(id: berserkID, in: context))
        #expect(berserk.catalogEntries.map(\.modeKey).sorted() == ["all", "best"])
        #expect(try PersistenceTestSupport.mangasByID(in: context).filter { $0.id == berserkID }.count == 1)
    }

    // MARK: - Catalog purge

    @Test func `purgeExpiredCatalog removes only the entries fetched before the cutoff`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1, now: Self.eightDaysAgo)
        try await actor.replaceCatalogPage(modeKey: "best", page: 1, per: 20, dtos: bestPage1)

        let purged = try await actor.purgeExpiredCatalog(olderThan: Self.sevenDays)

        #expect(purged == 20)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).isEmpty)
        #expect(try PersistenceTestSupport.catalogEntries(modeKey: "best", in: context).count == 20)
        // Purging the index never deletes mangas.
        let expectedIDs = Set(allPage1.map(\.id)).union(bestPage1.map(\.id))
        #expect(try PersistenceTestSupport.mangasByID(in: context).count == expectedIDs.count)
    }

    @Test func `purgeExpiredCatalog keeps entries fetched within the window`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1, now: Self.threeDaysAgo)

        let purged = try await actor.purgeExpiredCatalog(olderThan: Self.sevenDays)

        #expect(purged == 0)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count == 20)
    }

    // MARK: - Detail cache purge

    @Test func `purgeExpiredDetailCache deletes stale mangas that no index references`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1, now: Self.eightDaysAgo)
        // The best page refreshes the 4 shared mangas and indexes 16 new ones, all fresh.
        try await actor.replaceCatalogPage(modeKey: "best", page: 1, per: 20, dtos: bestPage1)
        _ = try await actor.purgeExpiredCatalog(olderThan: Self.sevenDays)

        let purged = try await actor.purgeExpiredDetailCache(olderThan: Self.sevenDays)

        let staleUnindexed = Set(allPage1.map(\.id)).subtracting(bestPage1.map(\.id))
        #expect(purged == staleUnindexed.count)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.mangasByID(in: context).map(\.id) == bestPage1.map(\.id).sorted())
    }

    @Test func `purgeExpiredDetailCache keeps stale mangas that are still indexed`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1, now: Self.eightDaysAgo)

        let purged = try await actor.purgeExpiredDetailCache(olderThan: Self.sevenDays)

        #expect(purged == 0)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.mangasByID(in: context).count == 20)
    }

    @Test func `purgeExpiredDetailCache keeps unindexed mangas cached within the window`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1, now: Self.threeDaysAgo)
        _ = try await actor.purgeExpiredCatalog(olderThan: Self.day)

        let purged = try await actor.purgeExpiredDetailCache(olderThan: Self.sevenDays)

        #expect(purged == 0)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).isEmpty)
        #expect(try PersistenceTestSupport.mangasByID(in: context).count == 20)
    }

    @Test func `purgeExpiredDetailCache keeps stale unindexed mangas that belong to the collection`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1, now: Self.eightDaysAgo)
        _ = try await actor.purgeExpiredCatalog(olderThan: Self.sevenDays)

        // Test-only write outside the actor: the collection API does not exist yet, and the
        // purge must honor the flag regardless of who set it.
        let keptID = 4
        let setup = PersistenceTestSupport.freshContext(container)
        let kept = try #require(try PersistenceTestSupport.manga(id: keptID, in: setup))
        kept.inCollection = true
        try setup.save()

        let purged = try await actor.purgeExpiredDetailCache(olderThan: Self.sevenDays)

        #expect(purged == 19)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.mangasByID(in: context).map(\.id) == [keptID])
    }
}
