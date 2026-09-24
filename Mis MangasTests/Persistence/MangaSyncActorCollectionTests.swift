//
//  MangaSyncActorCollectionTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// Detail cache, user collection and pending-operation outbox of the single write point of the
/// store. Every collection write is one transaction that leaves the entry and its queued server
/// operation together, so most tests assert both. Every test owns an in-memory container, so the
/// suite runs in parallel. Oracles: the literal values of the real fixtures, the fixed dates each
/// call receives, the fields the test itself chose to save, and what a fresh `ModelContext` reads
/// afterwards. A value returned by the actor is asserted only where that value is the behavior
/// (drain, snapshot, the blocked flag).
@Suite("MangaSyncActor collection and outbox")
struct MangaSyncActorCollectionTests {
    // Fixed clock: every date is an explicit instant, never the wall clock.
    private static let t1 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let t2 = Date(timeIntervalSinceReferenceDate: 800_000_100)
    private static let t3 = Date(timeIntervalSinceReferenceDate: 800_000_200)

    /// Monster (id 1) as `/search/manga/1` serves it: one author, Naoki Urasawa.
    private static let monsterID = 1
    private static let urasawaID = "54BE174C-2FE9-42C8-A842-85D291A6AEDD"
    /// Berserk (id 2) as `mangas_page.json` lists it: Kentarou Miura, then Studio Gaga.
    private static let berserkID = 2
    private static let miuraID = "6F0B6948-08C4-4761-8BE1-192E68AB0A2F"
    private static let studioGagaID = "0304C4E9-2D89-463A-8FDD-EEAB5B9D57B3"

    private let monster: MangaDTO
    private let berserk: MangaDTO

    init() throws {
        monster = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))
        let page = try PersistenceTestSupport.pageItems("mangas_page.json")
        berserk = try #require(page.first { $0.id == Self.berserkID })
    }

    /// The request an upsert operation carries, decoded with the app decoder. A missing payload
    /// is a recorded failure, never a crash.
    private static func request(in payload: Data?) throws -> UserMangaCollectionRequest {
        try JSONDecoder.app.decode(UserMangaCollectionRequest.self, from: #require(payload))
    }

    // MARK: - Detail cache

    @Test func `cacheDetail stores the manga with its author, stamped with the given date and outside the collection`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        let returnedID = try await actor.cacheDetail(monster, now: Self.t1)

        #expect(returnedID == Self.monsterID)
        let context = PersistenceTestSupport.freshContext(container)
        let mangas = try PersistenceTestSupport.mangasByID(in: context)
        #expect(mangas.map(\.id) == [Self.monsterID])
        let stored = try #require(mangas.first)
        #expect(stored.title == "Monster")
        #expect(stored.cachedAt == Self.t1)
        #expect(stored.updatedAt == Self.t1)
        #expect(!stored.inCollection)
        #expect(stored.authors.map(\.id.uuidString) == [Self.urasawaID])
        #expect(stored.authorOrder.map(\.uuidString) == [Self.urasawaID])
        #expect(try PersistenceTestSupport.fetchAll(Author.self, in: context).count == 1)
    }

    @Test func `cacheDetail keeps the server order of the authors`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        // Reversed so the expected order matches neither the fixture nor alphabetical order.
        let reordered = berserk.replacing(authors: Array(berserk.authors.reversed()))

        _ = try await actor.cacheDetail(reordered, now: Self.t1)

        let context = PersistenceTestSupport.freshContext(container)
        let stored = try #require(try PersistenceTestSupport.manga(id: Self.berserkID, in: context))
        #expect(stored.authorOrder.map(\.uuidString) == [Self.studioGagaID, Self.miuraID])
        #expect(stored.orderedAuthors.map(\.id.uuidString) == [Self.studioGagaID, Self.miuraID])
    }

    @Test func `cacheDetail twice refreshes the same manga instead of duplicating it`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        _ = try await actor.cacheDetail(monster, now: Self.t1)
        _ = try await actor.cacheDetail(monster.replacing(score: 7.5), now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let mangas = try PersistenceTestSupport.mangasByID(in: context)
        #expect(mangas.count == 1)
        let stored = try #require(mangas.first)
        #expect(stored.score == 7.5)
        #expect(stored.cachedAt == Self.t2)
        #expect(try PersistenceTestSupport.fetchAll(Author.self, in: context).count == 1)
    }

    @Test func `cacheDetail never touches the catalog index`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let page = try PersistenceTestSupport.pageItems("mangas_page.json")
        try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: page, now: Self.t1)

        _ = try await actor.cacheDetail(monster.replacing(score: 1.0), now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
        #expect(entries.count == page.count)
        #expect(entries.compactMap(\.manga?.id) == page.map(\.id))
        #expect(entries.allSatisfy { $0.fetchedAt == Self.t1 })
        #expect(try PersistenceTestSupport.mangasByID(in: context).count == page.count)
        #expect(try PersistenceTestSupport.manga(id: Self.monsterID, in: context)?.score == 1.0)
    }

    @Test func `cacheDetail of a manga in the collection keeps it in the collection and leaves its queued upsert alone`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1, 2], readingVolume: 2, completeCollection: false, now: Self.t1)

        _ = try await actor.cacheDetail(monster.replacing(score: 7.5), now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
        #expect(stored.score == 7.5)
        #expect(stored.inCollection)
        #expect(stored.collectionEntry?.volumesOwned == [1, 2])
        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).count == 1)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.map(\.operationType) == ["upsert"])
        #expect(operations.map(\.createdAt) == [Self.t1])
    }

    // MARK: - Collection entry

    @Test func `Saving an entry for a manga that is not stored throws notFound and writes nothing`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        do throws(PersistenceError) {
            try await actor.saveCollectionEntry(mangaID: 42, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
            Issue.record("Expected PersistenceError.notFound, but the save completed")
        } catch {
            switch error {
            case .notFound:
                break
            default:
                Issue.record("Expected PersistenceError.notFound, got \(error)")
            }
        }

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
        #expect(try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context).isEmpty)
        #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
    }

    @Test func `Saving an entry for a cached manga stores it, puts the manga in the collection and queues one upsert`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)

        try await actor.saveCollectionEntry(
            mangaID: Self.monsterID,
            volumesOwned: Array(1 ... 10),
            readingVolume: 7,
            completeCollection: false,
            now: Self.t2
        )

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.mangaID == Self.monsterID)
        #expect(entry.volumesOwned == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(entry.readingVolume == 7)
        #expect(!entry.completeCollection)
        #expect(entry.createdAt == Self.t2)
        #expect(entry.updatedAt == Self.t2)
        #expect(entry.manga?.id == Self.monsterID)

        let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
        #expect(stored.inCollection)
        #expect(stored.updatedAt == Self.t2)

        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        #expect(operation.operationType == "upsert")
        #expect(operation.mangaID == Self.monsterID)
        #expect(operation.createdAt == Self.t2)
        #expect(operation.attempts == 0)
        #expect(operation.blockedAt == nil)
        #expect(try Self.request(in: operation.payload) == UserMangaCollectionRequest(
            manga: Self.monsterID,
            completeCollection: false,
            volumesOwned: Array(1 ... 10),
            readingVolume: 7
        ))
    }

    @Test func `Saving unsorted volumes with duplicates stores them ascending and unique, in the entry and in the queued request`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)

        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [3, 1, 2, 2], readingVolume: 2, completeCollection: false, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.volumesOwned == [1, 2, 3])

        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        #expect(operation.operationType == "upsert")
        #expect(operation.mangaID == Self.monsterID)
        // The request mirrors the stored entry, so the volumes travel normalized, not as passed.
        #expect(try Self.request(in: operation.payload) == UserMangaCollectionRequest(
            manga: Self.monsterID,
            completeCollection: false,
            volumesOwned: [1, 2, 3],
            readingVolume: 2
        ))
    }

    // The store keeps volume numbers within 1…300 whatever the caller passes, the form or the
    // server: 300 leaves room for the longest series in print (about 200 volumes) while a
    // runaway count cannot fill the shared store, the widget or the upload payload.

    @Test func `Saving volumes and a reading volume outside 1 to 300 stores and queues them within that range`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)

        try await actor.saveCollectionEntry(
            mangaID: Self.monsterID,
            volumesOwned: [-1, 0, 1, 2, 300, 301, Int.max],
            readingVolume: Int.max,
            completeCollection: false,
            now: Self.t2
        )

        let context = PersistenceTestSupport.freshContext(container)
        let entry = try #require(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).first)
        #expect(entry.volumesOwned == [1, 2, 300])
        #expect(entry.readingVolume == 300)
        let operation = try #require(try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context).first)
        #expect(try Self.request(in: operation.payload) == UserMangaCollectionRequest(
            manga: Self.monsterID,
            completeCollection: false,
            volumesOwned: [1, 2, 300],
            readingVolume: 300
        ))
    }

    @Test func `Saving a reading volume of zero or below stores no reading volume`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)

        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: -5, completeCollection: false, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let entry = try #require(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).first)
        #expect(entry.readingVolume == nil)
    }

    @Test func `Upserting from a server DTO with volumes outside 1 to 300 stores them within that range`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let fixture = try #require(try Self.serverEntries().first)
        let dto = UserMangaCollectionDTO(
            id: fixture.id,
            manga: fixture.manga,
            volumesOwned: [0, 5, 1_000],
            readingVolume: 0,
            completeCollection: fixture.completeCollection
        )

        try await actor.upsertCollectionEntry(from: dto, now: Self.t1)

        let context = PersistenceTestSupport.freshContext(container)
        let entry = try #require(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).first)
        #expect(entry.volumesOwned == [5])
        #expect(entry.readingVolume == nil)
    }

    @Test func `Saving the same manga again updates its only entry, keeps the creation date and replaces the queued upsert`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: Array(1 ... 10), readingVolume: 7, completeCollection: false, now: Self.t1)

        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: Array(1 ... 18), readingVolume: nil, completeCollection: true, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.volumesOwned == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18])
        #expect(entry.readingVolume == nil)
        #expect(entry.completeCollection)
        #expect(entry.createdAt == Self.t1)
        #expect(entry.updatedAt == Self.t2)

        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        #expect(operation.operationType == "upsert")
        #expect(operation.createdAt == Self.t2)
        #expect(try Self.request(in: operation.payload) == UserMangaCollectionRequest(
            manga: Self.monsterID,
            completeCollection: true,
            volumesOwned: Array(1 ... 18),
            readingVolume: nil
        ))
    }

    @Test func `One hundred concurrent saves of the same manga leave a single entry and a single upsert that matches it`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        let mangaID = Self.monsterID

        try await withThrowingTaskGroup(of: Void.self) { group in
            for volume in 1 ... 100 {
                group.addTask {
                    try await actor.saveCollectionEntry(mangaID: mangaID, volumesOwned: [volume], readingVolume: nil, completeCollection: false, now: Self.t1)
                }
            }
            try await group.waitForAll()
        }

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.count == 1)
        // Whichever write landed last wins; it must be one of the hundred, intact.
        let entry = try #require(entries.first)
        #expect(entry.volumesOwned.count == 1)
        #expect(entry.volumesOwned.allSatisfy { (1 ... 100).contains($0) })

        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        #expect(operation.operationType == "upsert")
        #expect(try Self.request(in: operation.payload).volumesOwned == entry.volumesOwned)
    }

    @Test func `Removing a saved entry takes the manga out of the collection, keeps the manga and replaces the upsert with a delete`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1, 2], readingVolume: 1, completeCollection: false, now: Self.t1)

        try await actor.removeCollectionEntry(mangaID: Self.monsterID, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        #expect(operation.operationType == "delete")
        #expect(operation.mangaID == Self.monsterID)
        #expect(operation.payload == nil)
        #expect(operation.createdAt == Self.t2)

        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
        let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
        #expect(!stored.inCollection)
        #expect(stored.collectionEntry == nil)
        #expect(stored.updatedAt == Self.t2)
    }

    @Test func `Removing a manga that has no local entry still queues its delete and creates nothing`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        try await actor.removeCollectionEntry(mangaID: 42, now: Self.t1)

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        #expect(operation.operationType == "delete")
        #expect(operation.mangaID == 42)
        #expect(operation.payload == nil)
        #expect(operation.createdAt == Self.t1)
        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
        #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
    }

    @Test func `Interleaved concurrent saves and removes leave one operation that matches the final entry`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        let mangaID = Self.monsterID

        try await withThrowingTaskGroup(of: Void.self) { group in
            for pass in 1 ... 50 {
                group.addTask {
                    try await actor.saveCollectionEntry(mangaID: mangaID, volumesOwned: [pass], readingVolume: pass, completeCollection: false, now: Self.t1)
                }
                group.addTask {
                    try await actor.removeCollectionEntry(mangaID: mangaID, now: Self.t1)
                }
            }
            try await group.waitForAll()
        }

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        #expect(operation.mangaID == mangaID)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.count <= 1)
        let stored = try #require(try PersistenceTestSupport.manga(id: mangaID, in: context))
        // Whichever write landed last, the queue tells the server exactly what the store holds.
        if let entry = entries.first {
            #expect(stored.inCollection)
            #expect(operation.operationType == "upsert")
            let request = try Self.request(in: operation.payload)
            #expect(request.readingVolume == entry.readingVolume)
            #expect(request.volumesOwned == entry.volumesOwned)
        } else {
            #expect(!stored.inCollection)
            #expect(operation.operationType == "delete")
            #expect(operation.payload == nil)
        }
    }

    @Test func `Upserting from the server DTOs stores the nested mangas, their authors and the entries`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let dtos = try JSONDecoder.app.decode([UserMangaCollectionDTO].self, from: TestFixtures.data("collection_response.json"))

        for dto in dtos {
            try await actor.upsertCollectionEntry(from: dto, now: Self.t1)
        }

        let context = PersistenceTestSupport.freshContext(container)
        let mangas = try PersistenceTestSupport.mangasByID(in: context)
        #expect(mangas.map(\.id) == [Self.monsterID, Self.berserkID])
        #expect(mangas.map(\.title) == ["Monster", "Berserk"])
        #expect(mangas.allSatisfy { $0.inCollection })
        #expect(try PersistenceTestSupport.fetchAll(Author.self, in: context).count == 3)

        let storedMonster = try #require(mangas.first)
        #expect(storedMonster.authors.map(\.id.uuidString) == [Self.urasawaID])
        let storedBerserk = try #require(mangas.last)
        #expect(storedBerserk.authorOrder.map(\.uuidString) == [Self.miuraID, Self.studioGagaID])

        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context, sortBy: [SortDescriptor(\.mangaID)])
        #expect(entries.map(\.mangaID) == [Self.monsterID, Self.berserkID])
        let monsterEntry = try #require(entries.first)
        #expect(monsterEntry.volumesOwned == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18])
        #expect(monsterEntry.readingVolume == 12)
        #expect(monsterEntry.completeCollection)
        #expect(monsterEntry.manga?.id == Self.monsterID)
        let berserkEntry = try #require(entries.last)
        #expect(berserkEntry.volumesOwned == [1, 2, 3])
        #expect(berserkEntry.readingVolume == nil)
        #expect(!berserkEntry.completeCollection)
        #expect(berserkEntry.manga?.id == Self.berserkID)
    }

    /// The entries of `collection_response.json`: Monster first, then Berserk.
    private static func serverEntries() throws -> [UserMangaCollectionDTO] {
        try JSONDecoder.app.decode([UserMangaCollectionDTO].self, from: TestFixtures.data("collection_response.json"))
    }

    /// Local id of the stored entry of `mangaID`, read through a fresh context.
    private static func entryID(mangaID: Int, in container: ModelContainer) throws -> UUID {
        let context = PersistenceTestSupport.freshContext(container)
        let descriptor = FetchDescriptor<UserCollectionEntry>(predicate: #Predicate { $0.mangaID == mangaID })
        return try #require(try context.fetch(descriptor).first?.id)
    }

    @Test func `Upserting from the server DTOs never queues an operation`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        for dto in try Self.serverEntries() {
            try await actor.upsertCollectionEntry(from: dto, now: Self.t1)
        }

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).count == 2)
        #expect(try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context).isEmpty)
    }

    @Test func `Upserting from a server DTO stamps the nested manga with the given date`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let dto = try #require(try Self.serverEntries().first)

        try await actor.upsertCollectionEntry(from: dto, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
        #expect(stored.cachedAt == Self.t2)
        #expect(stored.updatedAt == Self.t2)
    }

    @Test func `Upserting from a server DTO gives the entry a local id, not the server one`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let dto = try #require(try Self.serverEntries().first)
        let serverID = try #require(UUID(uuidString: "7C1E2A54-3B9D-4F6A-9E21-5D8C0B4F7A13"))

        try await actor.upsertCollectionEntry(from: dto, now: Self.t1)

        let context = PersistenceTestSupport.freshContext(container)
        let entry = try #require(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).first)
        #expect(entry.mangaID == Self.monsterID)
        #expect(entry.id != serverID)
    }

    @Test func `Upserting from a server DTO with unsorted duplicate volumes stores them ascending and unique`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let fixture = try #require(try Self.serverEntries().first)
        let dto = UserMangaCollectionDTO(
            id: fixture.id,
            manga: fixture.manga,
            volumesOwned: [3, 1, 3, 2],
            readingVolume: fixture.readingVolume,
            completeCollection: fixture.completeCollection
        )

        try await actor.upsertCollectionEntry(from: dto, now: Self.t1)

        let context = PersistenceTestSupport.freshContext(container)
        let entry = try #require(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).first)
        #expect(entry.volumesOwned == [1, 2, 3])
    }

    @Test func `Upserting from a server DTO over an existing entry keeps its local id and creation date`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1, 2], readingVolume: 1, completeCollection: false, now: Self.t1)
        let localID = try Self.entryID(mangaID: Self.monsterID, in: container)
        let dto = try #require(try Self.serverEntries().first)

        try await actor.upsertCollectionEntry(from: dto, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.id == localID)
        #expect(entry.createdAt == Self.t1)
        #expect(entry.updatedAt == Self.t2)
        // The server values replace the local ones.
        #expect(entry.volumesOwned == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18])
        #expect(entry.readingVolume == 12)
        #expect(entry.completeCollection)
    }

    @Test func `Upserting from a server DTO equal to the stored entry refreshes the manga but does not stamp the entry`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        // The same user fields the fixture carries for Monster.
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: Array(1 ... 18), readingVolume: 12, completeCollection: true, now: Self.t1)
        let dto = try #require(try Self.serverEntries().first)

        try await actor.upsertCollectionEntry(from: dto, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.createdAt == Self.t1)
        #expect(entry.updatedAt == Self.t1)
        let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
        #expect(stored.cachedAt == Self.t2)
    }

    @Test func `collectionSnapshot returns every stored entry with its fields`() async throws {
        let (actor, _) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        _ = try await actor.cacheDetail(berserk, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1, 2, 3], readingVolume: 2, completeCollection: false, now: Self.t2)
        try await actor.saveCollectionEntry(mangaID: Self.berserkID, volumesOwned: [5, 4], readingVolume: nil, completeCollection: true, now: Self.t3)

        let snapshot = try await actor.collectionSnapshot()

        // The snapshot promises no order: sort it here.
        let sorted = snapshot.sorted { $0.mangaID < $1.mangaID }
        #expect(sorted.map(\.mangaID) == [Self.monsterID, Self.berserkID])
        let first = try #require(sorted.first)
        #expect(first.volumesOwned == [1, 2, 3])
        #expect(first.readingVolume == 2)
        #expect(!first.completeCollection)
        #expect(first.updatedAt == Self.t2)
        let second = try #require(sorted.last)
        #expect(second.volumesOwned == [4, 5])
        #expect(second.readingVolume == nil)
        #expect(second.completeCollection)
        #expect(second.updatedAt == Self.t3)
    }

    // MARK: - Outbox

    /// Id of the stored operation of `mangaID`, read through a fresh context so the test never
    /// depends on the actor to learn it.
    private static func operationID(mangaID: Int, in container: ModelContainer) throws -> UUID {
        let context = PersistenceTestSupport.freshContext(container)
        let descriptor = FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.mangaID == mangaID })
        return try #require(try context.fetch(descriptor).first?.id)
    }

    @Test func `Removing after saving the same manga leaves only its delete and the other manga's upsert untouched`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        _ = try await actor.cacheDetail(berserk, now: Self.t1)

        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.berserkID, volumesOwned: [2], readingVolume: 2, completeCollection: true, now: Self.t1)
        try await actor.removeCollectionEntry(mangaID: Self.monsterID, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context, sortBy: [SortDescriptor(\.mangaID)])
        #expect(operations.map(\.mangaID) == [Self.monsterID, Self.berserkID])
        let replaced = try #require(operations.first)
        #expect(replaced.operationType == "delete")
        #expect(replaced.payload == nil)
        #expect(replaced.createdAt == Self.t2)
        // The other manga's operation is not part of the replacement.
        let untouched = try #require(operations.last)
        #expect(untouched.operationType == "upsert")
        #expect(untouched.createdAt == Self.t1)
        #expect(try Self.request(in: untouched.payload) == UserMangaCollectionRequest(
            manga: Self.berserkID,
            completeCollection: true,
            volumesOwned: [2],
            readingVolume: 2
        ))
    }

    @Test func `Draining returns the operations oldest first and keeps them stored`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(berserk, now: Self.t1)
        _ = try await actor.cacheDetail(monster.replacing(id: 3), now: Self.t1)
        // Queued out of chronological order, so insertion order cannot pass for FIFO.
        try await actor.saveCollectionEntry(mangaID: 3, volumesOwned: [3], readingVolume: nil, completeCollection: false, now: Self.t3)
        try await actor.removeCollectionEntry(mangaID: Self.monsterID, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.berserkID, volumesOwned: [2], readingVolume: nil, completeCollection: false, now: Self.t2)

        let drained = try await actor.drainPendingOperations()

        #expect(drained.map(\.mangaID) == [Self.monsterID, Self.berserkID, 3])
        #expect(drained.map(\.type) == [.delete, .upsert, .upsert])
        #expect(drained.map(\.attempts) == [0, 0, 0])
        #expect(drained.first?.payload == nil)
        // Each upsert carries the volumes saved for its own manga.
        let requests = try drained.dropFirst().map { try Self.request(in: $0.payload) }
        #expect(requests.map(\.manga) == [Self.berserkID, 3])
        #expect(requests.map(\.volumesOwned) == [[2], [3]])
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context).count == 3)
    }

    @Test func `The third failure blocks an operation and takes it out of the drain`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.removeCollectionEntry(mangaID: Self.berserkID, now: Self.t2)
        let failingID = try Self.operationID(mangaID: Self.monsterID, in: container)

        let first = try await actor.markOperationFailed(id: failingID, error: "first", now: Self.t1)
        let second = try await actor.markOperationFailed(id: failingID, error: "second", now: Self.t2)
        let drainedBeforeBlocking = try await actor.drainPendingOperations()
        let third = try await actor.markOperationFailed(id: failingID, error: "third", now: Self.t3)
        let drainedAfterBlocking = try await actor.drainPendingOperations()

        #expect([first, second, third] == [false, false, true])
        #expect(drainedBeforeBlocking.map(\.mangaID) == [Self.monsterID, Self.berserkID])
        #expect(drainedBeforeBlocking.first?.attempts == 2)
        #expect(drainedAfterBlocking.map(\.mangaID) == [Self.berserkID])

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context, sortBy: [SortDescriptor(\.mangaID)])
        #expect(operations.count == 2)
        let blocked = try #require(operations.first)
        #expect(blocked.attempts == 3)
        #expect(blocked.lastError == "third")
        #expect(blocked.blockedAt == Self.t3)
    }

    @Test func `unblockAll returns a blocked operation to the drain with its attempts and last error reset`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        let blockedID = try Self.operationID(mangaID: Self.monsterID, in: container)
        for _ in 1 ... 3 {
            _ = try await actor.markOperationFailed(id: blockedID, error: "offline", now: Self.t2)
        }

        try await actor.unblockAll()

        let drained = try await actor.drainPendingOperations()
        #expect(drained.map(\.id) == [blockedID])
        #expect(drained.map(\.attempts) == [0])
        let context = PersistenceTestSupport.freshContext(container)
        let stored = try #require(try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context).first)
        #expect(stored.blockedAt == nil)
        #expect(stored.attempts == 0)
        #expect(stored.lastError == nil)
    }

    @Test func `Completing an operation deletes only that operation`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.removeCollectionEntry(mangaID: Self.berserkID, now: Self.t2)
        let completedID = try Self.operationID(mangaID: Self.monsterID, in: container)

        try await actor.markOperationCompleted(id: completedID)

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.map(\.mangaID) == [Self.berserkID])
        // Completing the send never touches the entry it carried.
        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).map(\.mangaID) == [Self.monsterID])
    }

    @Test func `pendingMangaIDs returns each manga with a queued operation once`() async throws {
        let (actor, _) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        _ = try await actor.cacheDetail(monster.replacing(id: 5), now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: 5, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.removeCollectionEntry(mangaID: Self.monsterID, now: Self.t2)
        try await actor.removeCollectionEntry(mangaID: Self.berserkID, now: Self.t3)

        let ids = try await actor.pendingMangaIDs()

        #expect(ids == [Self.monsterID, Self.berserkID, 5])
    }

    @Test func `pendingMangaIDs includes the mangas whose operation is blocked`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.removeCollectionEntry(mangaID: Self.berserkID, now: Self.t2)
        let blockedID = try Self.operationID(mangaID: Self.monsterID, in: container)
        var isBlocked = false
        for _ in 1 ... 3 {
            isBlocked = try await actor.markOperationFailed(id: blockedID, error: "offline", now: Self.t3)
        }

        let ids = try await actor.pendingMangaIDs()

        #expect(isBlocked)
        #expect(ids == [Self.monsterID, Self.berserkID])
    }

    @Test func `Writing a manga again moves its operation behind the ones queued in between`() async throws {
        let (actor, _) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        _ = try await actor.cacheDetail(berserk, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.berserkID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t2)
        try await actor.removeCollectionEntry(mangaID: Self.monsterID, now: Self.t3)

        let drained = try await actor.drainPendingOperations()

        #expect(drained.map(\.mangaID) == [Self.berserkID, Self.monsterID])
        #expect(drained.map(\.type) == [.upsert, .delete])
    }

    @Test func `Completing an operation that was replaced while in flight leaves the replacement queued`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        let inFlightID = try Self.operationID(mangaID: Self.monsterID, in: container)
        // The intention that replaces the one being sent.
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1, 2], readingVolume: nil, completeCollection: true, now: Self.t2)

        try await actor.markOperationCompleted(id: inFlightID)

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let replacement = try #require(operations.first)
        #expect(replacement.id != inFlightID)
        #expect(replacement.mangaID == Self.monsterID)
        #expect(replacement.operationType == "upsert")
        #expect(replacement.createdAt == Self.t2)
        #expect(try Self.request(in: replacement.payload) == UserMangaCollectionRequest(
            manga: Self.monsterID,
            completeCollection: true,
            volumesOwned: [1, 2],
            readingVolume: nil
        ))
    }

    @Test func `Failing an operation that was replaced while in flight reports not blocked and leaves the replacement untouched`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        _ = try await actor.cacheDetail(monster, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        let inFlightID = try Self.operationID(mangaID: Self.monsterID, in: container)
        try await actor.removeCollectionEntry(mangaID: Self.monsterID, now: Self.t2)

        let isBlocked = try await actor.markOperationFailed(id: inFlightID, error: "timeout", maxAttempts: 1, now: Self.t3)

        #expect(!isBlocked)
        let context = PersistenceTestSupport.freshContext(container)
        let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
        #expect(operations.count == 1)
        let replacement = try #require(operations.first)
        #expect(replacement.id != inFlightID)
        #expect(replacement.operationType == "delete")
        #expect(replacement.attempts == 0)
        #expect(replacement.lastError == nil)
        #expect(replacement.blockedAt == nil)
    }
}
