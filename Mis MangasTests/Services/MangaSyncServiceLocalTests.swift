//
//  MangaSyncServiceLocalTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// The detail cache and the local half of the collection, as the service orchestrates them:
    /// network (mocked transport) → decode → `MangaSyncActor` → store, and every collection write
    /// followed by its queued server operation. Oracles: the literal values of `manga_monster.json`,
    /// the request `URLSession` handed to the mock, and what a fresh `ModelContext` reads afterwards.
    /// Seeding goes straight through the actor, so a failure here points at the service.
    @Suite("MangaSyncService — local collection")
    struct MangaSyncServiceLocalTests {
        /// Monster (id 1) as `/search/manga/1` serves it.
        private static let monsterID = 1
        private static let monsterTitle = "Monster"
        private static let monsterScore = 9.15

        private let service: MangaSyncService
        private let actor: MangaSyncActor
        private let container: ModelContainer
        private let monster: MangaDTO

        init() throws {
            CatalogMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            actor = made.actor
            container = made.container
            let repository = DefaultMangaRepositoryTest()
            service = MangaSyncService(
                syncActor: actor,
                mangaRepository: repository,
                taxonomyCache: TaxonomyCacheActor(mangaRepository: repository)
            )
            monster = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))
        }

        // MARK: - cacheDetail

        @Test func `cacheDetail stores the manga outside the collection without touching the network`() async throws {
            let returnedID = try await service.cacheDetail(monster)

            #expect(returnedID == Self.monsterID)
            #expect(CatalogMockScenario.hits(.mangaByID) == 0)
            let context = PersistenceTestSupport.freshContext(container)
            let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
            #expect(stored.title == Self.monsterTitle)
            #expect(stored.cachedAt != nil)
            #expect(!stored.inCollection)
        }

        // MARK: - refreshDetail

        @Test func `refreshDetail requests the manga by id and stores what the server served`() async throws {
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))

            try await service.refreshDetail(mangaID: Self.monsterID)

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByID))
            #expect(sent.method == "GET")
            #expect(sent.path == "/search/manga/1")
            let context = PersistenceTestSupport.freshContext(container)
            let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
            #expect(stored.title == Self.monsterTitle)
            #expect(stored.score == Self.monsterScore)
            #expect(stored.cachedAt != nil)
        }

        @Test func `refreshDetail overwrites a stale cached manga with the served fields`() async throws {
            // Seeded with a score the fixture never carries, so only a real refresh can replace it.
            _ = try await actor.cacheDetail(monster.replacing(score: 1.0))
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))

            try await service.refreshDetail(mangaID: Self.monsterID)

            let context = PersistenceTestSupport.freshContext(container)
            let mangas = try PersistenceTestSupport.mangasByID(in: context)
            #expect(mangas.map(\.id) == [Self.monsterID])
            let stored = try #require(mangas.first)
            #expect(stored.score == Self.monsterScore)
        }

        @Test func `refreshDetail of an unknown manga surfaces notFound and stores nothing`() async throws {
            CatalogMockScenario.set(.mangaByID, .status(404))

            await expectAPIError(.notFound) {
                try await service.refreshDetail(mangaID: Self.monsterID)
            }

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
        }

        // MARK: - saveCollectionEntry

        @Test func `saveCollectionEntry stores the entry and queues one upsert carrying what was stored`() async throws {
            _ = try await actor.cacheDetail(monster)

            try await service.saveCollectionEntry(
                mangaID: Self.monsterID,
                volumesOwned: [3, 1, 2, 2],
                readingVolume: 2,
                completeCollection: false
            )

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
            #expect(entries.count == 1)
            let entry = try #require(entries.first)
            #expect(entry.mangaID == Self.monsterID)
            #expect(entry.volumesOwned == [1, 2, 3])
            #expect(entry.readingVolume == 2)
            #expect(!entry.completeCollection)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
            #expect(manga.inCollection)

            let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
            #expect(operations.count == 1)
            let operation = try #require(operations.first)
            #expect(operation.operationType == "upsert")
            #expect(operation.mangaID == Self.monsterID)
            let payload = try #require(operation.payload)
            let request = try JSONDecoder.app.decode(UserMangaCollectionRequest.self, from: payload)
            // The request mirrors the stored entry, so the volumes travel normalized
            // (ascending, no duplicates), not as the caller passed them.
            #expect(request == UserMangaCollectionRequest(
                manga: Self.monsterID,
                completeCollection: false,
                volumesOwned: [1, 2, 3],
                readingVolume: 2
            ))
        }

        @Test func `Saving the same manga twice keeps one entry and only the last queued upsert`() async throws {
            _ = try await actor.cacheDetail(monster)

            try await service.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1, 2], readingVolume: 2, completeCollection: false)
            try await service.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [4, 1, 2, 3], readingVolume: 4, completeCollection: true)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
            #expect(entries.count == 1)
            let entry = try #require(entries.first)
            #expect(entry.volumesOwned == [1, 2, 3, 4])
            #expect(entry.readingVolume == 4)
            #expect(entry.completeCollection)

            let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
            #expect(operations.count == 1)
            let operation = try #require(operations.first)
            #expect(operation.operationType == "upsert")
            let payload = try #require(operation.payload)
            let request = try JSONDecoder.app.decode(UserMangaCollectionRequest.self, from: payload)
            #expect(request == UserMangaCollectionRequest(
                manga: Self.monsterID,
                completeCollection: true,
                volumesOwned: [1, 2, 3, 4],
                readingVolume: 4
            ))
        }

        @Test func `saveCollectionEntry for a manga that is not stored throws notFound and queues nothing`() async throws {
            do throws(PersistenceError) {
                try await service.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1], readingVolume: nil, completeCollection: false)
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
            #expect(try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context).isEmpty)
            #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
        }

        // MARK: - removeCollectionEntry

        @Test func `removeCollectionEntry drops the entry, keeps the manga and replaces the upsert with a delete`() async throws {
            _ = try await actor.cacheDetail(monster)
            try await service.saveCollectionEntry(mangaID: Self.monsterID, volumesOwned: [1, 2], readingVolume: 2, completeCollection: false)

            try await service.removeCollectionEntry(mangaID: Self.monsterID)

            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
            #expect(!manga.inCollection)

            let operations = try PersistenceTestSupport.fetchAll(PendingOperation.self, in: context)
            #expect(operations.count == 1)
            let operation = try #require(operations.first)
            #expect(operation.operationType == "delete")
            #expect(operation.mangaID == Self.monsterID)
            #expect(operation.payload == nil)
        }
    }
}
