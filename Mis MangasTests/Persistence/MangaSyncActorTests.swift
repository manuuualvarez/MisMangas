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

    // MARK: - Author order

    /// Author ids of Berserk (id 2) as `mangas_page.json` lists them: Kentarou Miura, then
    /// Studio Gaga.
    private static let berserkID = 2
    private static let miuraID = "6F0B6948-08C4-4761-8BE1-192E68AB0A2F"
    private static let studioGagaID = "0304C4E9-2D89-463A-8FDD-EEAB5B9D57B3"

    @Test func `Upsert keeps the server order of a manga's authors`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)

        let context = PersistenceTestSupport.freshContext(container)
        let berserk = try #require(try PersistenceTestSupport.manga(id: Self.berserkID, in: context))
        #expect(berserk.authorOrder.map(\.uuidString) == [Self.miuraID, Self.studioGagaID])
        #expect(berserk.orderedAuthors.map(\.id.uuidString) == [Self.miuraID, Self.studioGagaID])
        #expect(berserk.primaryAuthorName == "Kentarou Miura")
    }

    @Test func `Refreshing a manga whose authors the server reordered stores the new order`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let reordered = allPage1.map { dto in
            dto.id == Self.berserkID ? dto.replacing(authors: Array(dto.authors.reversed())) : dto
        }

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: reordered)

        let context = PersistenceTestSupport.freshContext(container)
        let berserk = try #require(try PersistenceTestSupport.manga(id: Self.berserkID, in: context))
        #expect(berserk.authorOrder.map(\.uuidString) == [Self.studioGagaID, Self.miuraID])
        #expect(berserk.orderedAuthors.map(\.id.uuidString) == [Self.studioGagaID, Self.miuraID])
        #expect(berserk.primaryAuthorName == "Studio Gaga")
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

    // MARK: - Indexed count

    @Test func `indexedCount reports the 20 entries of page 1 and the 40 of page 2`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        let afterPage1 = try await actor.indexedCount(modeKey: "all")
        try await actor.replaceCatalogPage(modeKey: "all", page: 2, per: 20, dtos: allPage2)
        let afterPage2 = try await actor.indexedCount(modeKey: "all")

        let context = PersistenceTestSupport.freshContext(container)
        let stored = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count
        #expect(afterPage1 == allPage1.count)
        #expect(afterPage2 == allPage1.count + allPage2.count)
        #expect(afterPage2 == stored)
    }

    @Test func `indexedCount of a mode that was never indexed is zero`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)

        let best = try await actor.indexedCount(modeKey: "best")

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.catalogEntries(modeKey: "best", in: context).isEmpty)
        #expect(best == 0)
    }

    @Test func `Reindexing page 1 takes the count of the mode back to 20`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "all", page: 2, per: 20, dtos: allPage2)

        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)

        let count = try await actor.indexedCount(modeKey: "all")
        let context = PersistenceTestSupport.freshContext(container)
        let stored = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count
        #expect(count == allPage1.count)
        #expect(count == stored)
    }

    @Test func `Indexing a second mode leaves the count of the first one untouched`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)
        try await actor.replaceCatalogPage(modeKey: "all", page: 2, per: 20, dtos: allPage2)

        try await actor.replaceCatalogPage(modeKey: "best", page: 1, per: 20, dtos: bestPage1)

        let all = try await actor.indexedCount(modeKey: "all")
        let best = try await actor.indexedCount(modeKey: "best")
        let context = PersistenceTestSupport.freshContext(container)
        let storedAll = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count
        let storedBest = try PersistenceTestSupport.catalogEntries(modeKey: "best", in: context).count
        // The two modes share mangas, so a count of stored mangas would not add up to these two.
        #expect(!sharedIDs.isEmpty)
        #expect(all == allPage1.count + allPage2.count)
        #expect(best == bestPage1.count)
        #expect(all == storedAll)
        #expect(best == storedBest)
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

        // Test-only write outside the actor: the purge must honor the flag regardless of who
        // set it, so the flag is set directly rather than through a collection save.
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

    // MARK: - Cancellation

    @Test func `A page written by a task cancelled before it reached the actor throws cancelled and indexes nothing`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        let result = await Self.replaceAfterCancelling(actor, modeKey: "best", dtos: bestPage1)

        let error = #expect(throws: PersistenceError.self) { try result.get() }
        if let error {
            #expect(Self.isCancelled(error), "Expected PersistenceError.cancelled, got \(error)")
        }
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.catalogEntries(modeKey: "best", in: context).isEmpty)
        #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
    }

    @Test func `A cancelled page write keeps the index the mode already had and inserts none of its mangas`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: allPage1)

        // Page 1 again, but with mangas the store has never seen: had it been written, it would
        // replace every entry of the mode and add 20 mangas.
        let result = await Self.replaceAfterCancelling(actor, modeKey: "all", dtos: allPage2)

        let error = #expect(throws: PersistenceError.self) { try result.get() }
        if let error {
            #expect(Self.isCancelled(error), "Expected PersistenceError.cancelled, got \(error)")
        }
        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
        #expect(entries.map(\.ordinal) == Array(0 ..< 20))
        #expect(entries.compactMap(\.manga?.id) == allPage1.map(\.id))
        #expect(try PersistenceTestSupport.mangasByID(in: context).map(\.id) == allPage1.map(\.id).sorted())
    }

    /// Calls `replaceCatalogPage` for page 1 of `modeKey` from an unstructured task that is already
    /// cancelled when it reaches the actor, and returns how that call ended. The task first waits
    /// for a signal the test sends only after `cancel()`; the wait ends on that signal or on the
    /// cancellation itself, both of which come after `cancel()`, so the order holds without sleeping.
    private static func replaceAfterCancelling(
        _ actor: MangaSyncActor,
        modeKey: String,
        dtos: [MangaDTO]
    ) async -> Result<Void, any Error> {
        let (signal, emit) = AsyncStream.makeStream(of: Void.self)
        let write = Task {
            for await _ in signal {
                break
            }
            try await actor.replaceCatalogPage(modeKey: modeKey, page: 1, per: 20, dtos: dtos)
        }
        write.cancel()
        emit.yield()
        emit.finish()
        return await write.result
    }

    /// `PersistenceError` carries `any Error` payloads and is not `Equatable`: match the case.
    private static func isCancelled(_ error: PersistenceError) -> Bool {
        if case .cancelled = error { true } else { false }
    }
}
