//
//  MangaDetailViewModelTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// The detail refresh driven through the real pipeline: ViewModel → `MangaSyncService` →
    /// mocked transport → decode → `MangaSyncActor` → store. The cached manga is seeded through
    /// the actor with a controlled `cachedAt` (its `now:` parameter), read back from a context of
    /// the container and handed to the ViewModel, which compares against the real clock.
    /// Oracles: how many times the mock was hit and on which path, the score of
    /// `manga_monster.json` (9.15) against a seeded score it never carries (1.0), and what a
    /// fresh `ModelContext` reads afterwards.
    @Suite("MangaDetailViewModel")
    @MainActor
    struct MangaDetailViewModelTests {
        /// Monster (id 1) as `/search/manga/1` serves it.
        private static let monsterID = 1
        private static let servedScore = 9.15
        /// A score the fixture never carries, so only a real refresh can replace it.
        private static let seededScore = 1.0

        private static let hour: TimeInterval = 60 * 60
        private static let day: TimeInterval = 24 * hour

        private let viewModel: MangaDetailViewModel
        private let actor: MangaSyncActor
        private let container: ModelContainer
        private let monster: MangaDTO

        init() throws {
            CatalogMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            actor = made.actor
            container = made.container
            let repository = DefaultMangaRepositoryTest()
            let service = MangaSyncService(
                syncActor: actor,
                mangaRepository: repository,
                taxonomyCache: TaxonomyCacheActor(mangaRepository: repository)
            )
            viewModel = MangaDetailViewModel(syncService: service)
            monster = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))
        }

        /// Stores Monster with the seeded score, as if it had arrived from the server `age` ago.
        private func seedMonster(cachedAgo age: TimeInterval) async throws {
            _ = try await actor.cacheDetail(monster.replacing(score: Self.seededScore), now: .now.addingTimeInterval(-age))
        }

        /// The score a fresh context reads for Monster right now.
        private func storedScore() throws -> Double? {
            let context = PersistenceTestSupport.freshContext(container)
            return try PersistenceTestSupport.manga(id: Self.monsterID, in: context)?.score
        }

        // MARK: - refreshIfNeeded

        @Test func `A manga cached two hours ago is shown as is without asking the server`() async throws {
            try await seedMonster(cachedAgo: 2 * Self.hour)
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            let context = PersistenceTestSupport.freshContext(container)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))

            await viewModel.refreshIfNeeded(manga: manga)

            #expect(CatalogMockScenario.hits(.mangaByID) == 0)
            // Skipping a refresh is not a failure, and the screen ends idle.
            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.seededScore)
        }

        @Test func `A manga cached twenty-five hours ago is requested by id and the served score replaces the cached one`() async throws {
            try await seedMonster(cachedAgo: 25 * Self.hour)
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            let context = PersistenceTestSupport.freshContext(container)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))

            await viewModel.refreshIfNeeded(manga: manga)

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByID))
            #expect(sent.method == "GET")
            #expect(sent.path == "/search/manga/1")
            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.servedScore)
        }

        @Test func `A manga that was never cached counts as expired and is requested`() async throws {
            // The actor always stamps `cachedAt`, so a manga without it can only be one built
            // outside the store, as sample data is. Nothing is seeded: the refresh stores it.
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            let manga = monster.makeManga()
            #expect(manga.cachedAt == nil)

            await viewModel.refreshIfNeeded(manga: manga)

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            #expect(CatalogMockScenario.lastRequest(.mangaByID)?.path == "/search/manga/1")
            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            let context = PersistenceTestSupport.freshContext(container)
            let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
            #expect(stored.score == Self.servedScore)
            #expect(stored.cachedAt != nil)
        }

        @Test func `A manga in the collection is never refreshed automatically, even thirty days after caching it`() async throws {
            let thirtyDaysAgo = Date.now.addingTimeInterval(-30 * Self.day)
            _ = try await actor.cacheDetail(monster.replacing(score: Self.seededScore), now: thirtyDaysAgo)
            try await actor.saveCollectionEntry(
                mangaID: Self.monsterID,
                volumesOwned: [1, 2],
                readingVolume: 2,
                completeCollection: false,
                account: nil,
                now: thirtyDaysAgo
            )
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            let context = PersistenceTestSupport.freshContext(container)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
            #expect(manga.inCollection)

            await viewModel.refreshIfNeeded(manga: manga)

            #expect(CatalogMockScenario.hits(.mangaByID) == 0)
            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.seededScore)
        }

        @Test func `Without network an expired manga keeps its cached version and the failure is reported, not thrown`() async throws {
            try await seedMonster(cachedAgo: 25 * Self.hour)
            CatalogMockScenario.set(.mangaByID, .transportError(.notConnectedToInternet))
            let context = PersistenceTestSupport.freshContext(container)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))

            await viewModel.refreshIfNeeded(manga: manga)

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.seededScore)
            let error = try #require(viewModel.refreshError)
            #expect(APIErrorCase.transport.matches(error), "Expected APIError.transport, got \(error)")
        }

        @Test func `Cancelling the task that asked for the refresh is not reported as an error`() async throws {
            try await seedMonster(cachedAgo: 25 * Self.hour)
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            let viewModel = viewModel
            let container = container
            // Created on the main actor and cancelled before this test suspends, so the body
            // always starts already cancelled: no timing is involved.
            let task = Task {
                let context = PersistenceTestSupport.freshContext(container)
                let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
                await viewModel.refreshIfNeeded(manga: manga)
            }
            task.cancel()

            try await task.value

            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.seededScore)
        }

        // MARK: - refresh

        @Test func `A manual refresh asks the server even when the cache is recent`() async throws {
            try await seedMonster(cachedAgo: 2 * Self.hour)
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            let context = PersistenceTestSupport.freshContext(container)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))

            await viewModel.refresh(manga: manga)

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            #expect(CatalogMockScenario.lastRequest(.mangaByID)?.path == "/search/manga/1")
            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.servedScore)
        }

        @Test func `A manual refresh asks the server even for a manga in the collection`() async throws {
            let now = Date.now
            _ = try await actor.cacheDetail(monster.replacing(score: Self.seededScore), now: now)
            try await actor.saveCollectionEntry(
                mangaID: Self.monsterID,
                volumesOwned: [1, 2],
                readingVolume: 2,
                completeCollection: false,
                account: nil,
                now: now
            )
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            let context = PersistenceTestSupport.freshContext(container)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
            #expect(manga.inCollection)

            await viewModel.refresh(manga: manga)

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            #expect(viewModel.refreshError == nil)
            let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: PersistenceTestSupport.freshContext(container)))
            #expect(stored.score == Self.servedScore)
            // The refresh replaces the server fields only: the entry of the reader survives it.
            #expect(stored.inCollection)
            #expect(stored.collectionEntry?.readingVolume == 2)
        }

        @Test func `A refresh asked while another is in flight is skipped instead of sending a second request`() async throws {
            try await seedMonster(cachedAgo: 25 * Self.hour)
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            let viewModel = viewModel
            let container = container
            // Both tasks start on the main actor in the order they were created: the first one
            // runs until it waits on the network, so the second one always finds it in flight.
            let automatic = Task {
                let context = PersistenceTestSupport.freshContext(container)
                let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
                await viewModel.refreshIfNeeded(manga: manga)
            }
            let manual = Task {
                let context = PersistenceTestSupport.freshContext(container)
                let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
                await viewModel.refresh(manga: manga)
            }

            try await automatic.value
            try await manual.value

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.servedScore)
        }

        @Test func `A request the transport reports as cancelled is not reported as an error`() async throws {
            try await seedMonster(cachedAgo: 2 * Self.hour)
            CatalogMockScenario.set(.mangaByID, .transportError(.cancelled))
            let context = PersistenceTestSupport.freshContext(container)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))

            await viewModel.refresh(manga: manga)

            // The wire was touched, so this is the cancelled path and not a skipped refresh.
            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.seededScore)
        }

        @Test func `A refresh that succeeds after a failed one clears the error`() async throws {
            try await seedMonster(cachedAgo: 2 * Self.hour)
            CatalogMockScenario.set(.mangaByID, .transportError(.notConnectedToInternet))
            let context = PersistenceTestSupport.freshContext(container)
            let manga = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
            await viewModel.refresh(manga: manga)
            #expect(viewModel.refreshError != nil)
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))

            await viewModel.refresh(manga: manga)

            #expect(CatalogMockScenario.hits(.mangaByID) == 2)
            #expect(viewModel.refreshError == nil)
            #expect(!viewModel.isRefreshing)
            #expect(try storedScore() == Self.servedScore)
        }
    }
}
