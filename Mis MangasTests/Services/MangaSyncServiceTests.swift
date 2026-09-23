//
//  MangaSyncServiceTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// The whole pipeline behind a catalog page: endpoint → mocked transport → decode →
    /// `MangaSyncActor` → store. Oracles: the request `URLSession` handed to the mock, the ids,
    /// order and `metadata.total` of the served fixture, and what a fresh `ModelContext` reads
    /// afterwards.
    @Suite("MangaSyncService")
    struct MangaSyncServiceTests {
        private static let sevenDays: TimeInterval = 7 * 86400
        private static let eightDaysAgo = Date.now.addingTimeInterval(-8 * 86400)

        private let service: MangaSyncService
        private let actor: MangaSyncActor
        private let container: ModelContainer

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
        }

        // MARK: - loadCatalogPage

        @Test func `loadCatalogPage all page 2 requests list mangas and indexes ordinals 20 to 39`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            let expectedIDs = try PersistenceTestSupport.pageItems("mangas_page.json").map(\.id)

            let result = try await service.loadCatalogPage(mode: .all, page: 2, per: 20)

            #expect(result.received == 20)
            #expect(result.total == 64833)
            let sent = try #require(CatalogMockScenario.lastRequest(.listMangas))
            #expect(sent.method == "GET")
            #expect(sent.path == "/list/mangas")
            #expect(sent.queryValues == ["page": "2", "per": "20"])
            #expect(CatalogMockScenario.hits(.listMangas) == 1)
            #expect(CatalogMockScenario.hits(.listBestMangas) == 0)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(20 ..< 40))
            #expect(entries.compactMap(\.manga?.id) == expectedIDs)
            #expect(try PersistenceTestSupport.mangasByID(in: context).count == 20)
        }

        @Test func `loadCatalogPage best requests list bestMangas and indexes under the best mode`() async throws {
            CatalogMockScenario.set(.listBestMangas, .fixture("mangas_page_best.json"))
            let expectedIDs = try PersistenceTestSupport.pageItems("mangas_page_best.json").map(\.id)

            let result = try await service.loadCatalogPage(mode: .best, page: 1, per: 20)

            #expect(result.received == 20)
            #expect(result.total == 64833)
            let sent = try #require(CatalogMockScenario.lastRequest(.listBestMangas))
            #expect(sent.method == "GET")
            #expect(sent.path == "/list/bestMangas")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(CatalogMockScenario.hits(.listMangas) == 0)

            let context = PersistenceTestSupport.freshContext(container)
            let best = try PersistenceTestSupport.catalogEntries(modeKey: "best", in: context)
            #expect(best.map(\.ordinal) == Array(0 ..< 20))
            #expect(best.compactMap(\.manga?.id) == expectedIDs)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).isEmpty)
        }

        @Test func `loadCatalogPage reports fewer items on a short last page and still the server total`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page_empty.json"))

            let result = try await service.loadCatalogPage(mode: .all, page: 5, per: 20)

            #expect(result.received == 0)
            #expect(result.total == 64833)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).isEmpty)
        }

        // MARK: - indexedCount

        @Test func `indexedCount reports the 40 rows two pages of the same mode left indexed`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            _ = try await service.loadCatalogPage(mode: .all, page: 1, per: 20)
            _ = try await service.loadCatalogPage(mode: .all, page: 2, per: 20)

            let count = await service.indexedCount(mode: .all)

            let context = PersistenceTestSupport.freshContext(container)
            let stored = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count
            #expect(stored == 40)
            #expect(count == stored)
            // Both pages carried the same 20 mangas: what is counted is index rows, not mangas.
            #expect(try PersistenceTestSupport.mangasByID(in: context).count == 20)
        }

        @Test func `indexedCount of a mode never loaded is zero and asks the store, not the wire`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            _ = try await service.loadCatalogPage(mode: .all, page: 1, per: 20)

            let count = await service.indexedCount(mode: .best)

            #expect(count == 0)
            #expect(CatalogMockScenario.hits(.listBestMangas) == 0)
            // The store is not empty: the zero belongs to the mode asked for.
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count == 20)
        }

        // MARK: - Failures

        @Test func `A 500 surfaces serverError and leaves the store empty`() async throws {
            CatalogMockScenario.set(.listMangas, .status(500))

            await expectAPIError(.serverError) {
                try await service.loadCatalogPage(mode: .all, page: 1, per: 20)
            }

            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.fetchAll(CatalogEntry.self, in: context).isEmpty)
            #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
        }

        @Test func `A broken payload surfaces decoding and keeps the previous index`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            _ = try await service.loadCatalogPage(mode: .all, page: 1, per: 20)
            CatalogMockScenario.set(.listMangas, .json("{ \"metadata\": {} }"))

            await expectAPIError(.decoding) {
                try await service.loadCatalogPage(mode: .all, page: 1, per: 20)
            }

            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count == 20)
        }

        @Test func `A page that arrives after the task was cancelled surfaces cancelled and leaves the store empty`() async throws {
            let repository = CancellingMangaRepository()
            let cancellingService = MangaSyncService(
                syncActor: actor,
                mangaRepository: repository,
                taxonomyCache: TaxonomyCacheActor(mangaRepository: repository)
            )

            // A child task, so the fake cancels the load and not the test itself.
            let load = Task {
                try await cancellingService.loadCatalogPage(mode: .all, page: 1, per: 20)
            }
            await expectAPIError(.cancelled) {
                try await load.value
            }

            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.fetchAll(CatalogEntry.self, in: context).isEmpty)
            #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
        }

        // MARK: - bootstrap

        @Test func `bootstrap purges a catalog page older than seven days and reports the counts`() async throws {
            let dtos = try PersistenceTestSupport.pageItems("mangas_page.json")
            try await actor.replaceCatalogPage(modeKey: "all", page: 1, per: 20, dtos: dtos, now: Self.eightDaysAgo)

            let result = await service.bootstrap()

            #expect(result.catalog == 20)
            // The index is purged first, so the stale mangas it referenced are unindexed by the
            // time the detail purge runs and go with it.
            #expect(result.details == 20)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.fetchAll(CatalogEntry.self, in: context).isEmpty)
            #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
        }

        @Test func `bootstrap keeps a fresh catalog page`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            _ = try await service.loadCatalogPage(mode: .all, page: 1, per: 20)

            let result = await service.bootstrap()

            #expect(result.catalog == 0)
            #expect(result.details == 0)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count == 20)
        }

        @Test func `bootstrap on an empty store returns zero counts`() async {
            let result = await service.bootstrap()

            #expect(result.catalog == 0)
            #expect(result.details == 0)
            #expect(CatalogMockScenario.hits(.listMangas) == 0)
        }
    }
}
