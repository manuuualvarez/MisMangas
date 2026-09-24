//
//  SyncCoordinatorTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// `SyncCoordinator` over the real `MangaSyncService`, `CollectionRepository` (mocked
    /// transport) and `MangaSyncActor` (in-memory store). Interleavings are fixed without sleeping:
    /// a route answered `.held` keeps its request in flight until the test releases it, so the
    /// test decides what happens while a pass is running. Oracles: the uploads captured by the
    /// mock (order and count) and what a fresh `ModelContext` reads afterwards.
    @Suite("SyncCoordinator")
    struct SyncCoordinatorTests {
        private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

        private let actor: MangaSyncActor
        private let container: ModelContainer
        private let service: MangaSyncService
        private let coordinator: SyncCoordinator

        init() throws {
            CollectionMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            actor = made.actor
            container = made.container
            let mangaRepository = DefaultMangaRepositoryTest()
            let service = MangaSyncService(
                syncActor: made.actor,
                mangaRepository: mangaRepository,
                taxonomyCache: TaxonomyCacheActor(mangaRepository: mangaRepository),
                collectionRepository: DefaultCollectionRepositoryTest(security: FakeSecurity(token: "example.coordinator.token"))
            )
            self.service = service
            coordinator = SyncCoordinator(service: service)
        }

        private func queueUpsert(mangaID: Int, secondsAfterStart seconds: TimeInterval) async throws {
            try await actor.saveCollectionEntry(
                mangaID: mangaID,
                volumesOwned: [1],
                readingVolume: nil,
                completeCollection: false,
                now: Self.t0.addingTimeInterval(seconds)
            )
        }

        private func operations() throws -> [PendingOperation] {
            try CollectionTestSupport.operations(in: PersistenceTestSupport.freshContext(container))
        }

        @Test func `requestSync during a pass runs one more pass with the change saved meanwhile, and synchronize returns that last pass`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.setSequence(.collectionList, [.held])
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let coordinator = coordinator

            let caller = Task { try await coordinator.synchronize() }
            // The first pass has uploaded manga 1 and is now reading the server collection.
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionList, orUntilFinished: caller))
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            await coordinator.requestSync()
            CatalogMockScenario.release(.collectionList, with: CollectionMockScenario.emptyCollection)
            let result = try await caller.value

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1, 2])
            #expect(CollectionMockScenario.hits(.collectionList) == 2)
            #expect(result.applied == 1)
            #expect(try operations().isEmpty)
        }

        @Test func `Two synchronize calls never drain in parallel and upload each operation once, oldest first`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let coordinator = coordinator

            let first = Task { try await coordinator.synchronize() }
            let second = Task { try await coordinator.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: first))
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 1)
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            let firstResult = try await first.value
            let secondResult = try await second.value

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1, 2])
            // The second call may join the running pass or, if it arrives while that pass reads
            // the server collection, schedule one more; either way both callers wait for the
            // same task and get the result of its last pass.
            #expect((1...2).contains(CollectionMockScenario.hits(.collectionList)))
            #expect(firstResult.applied == secondResult.applied)
            #expect(firstResult.upserted == secondResult.upserted)
            #expect(firstResult.removed == secondResult.removed)
            #expect(try operations().isEmpty)
        }

        @Test func `A caller that goes away does not cancel the pass it started`() async throws {
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let coordinator = coordinator

            let caller = Task { try await coordinator.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: caller))
            caller.cancel()
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            _ = await caller.result

            #expect(try operations().isEmpty)
            #expect(CollectionMockScenario.hits(.collectionList) == 1)
        }

        @Test func `stop cancels the running pass, sends nothing after it returns and leaves the queue for the next pass`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let coordinator = coordinator

            let caller = Task { try await coordinator.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: caller))
            await coordinator.stop()
            _ = await caller.result

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 1)
            #expect(CollectionMockScenario.hits(.collectionList) == 0)
            #expect(try operations().map(\.mangaID) == [1, 2])

            _ = try await coordinator.synchronize()

            #expect(try operations().isEmpty)
        }

        @Test func `sessionExpired reaches the caller with the queue intact, and the next synchronize runs again`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            CollectionMockScenario.setSequence(.collectionUpsert, [.status(401)])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            await expectSessionExpired {
                try await coordinator.synchronize()
            }
            #expect(try operations().map(\.mangaID) == [1, 2])
            #expect(CollectionMockScenario.hits(.collectionList) == 0)

            let result = try await coordinator.synchronize()

            #expect(result.applied == 2)
            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1, 1, 2])
            #expect(try operations().isEmpty)
        }

        @Test func `A hundred saves made offline are uploaded by one synchronize, one POST each, oldest first`() async throws {
            let ids = Array(1...100)
            try await CollectionTestSupport.storeMangas(ids, in: actor, now: Self.t0)
            for id in ids {
                try await service.saveCollectionEntry(mangaID: id, volumesOwned: [1], readingVolume: nil, completeCollection: false)
            }
            #expect(CollectionMockScenario.totalHits() == 0)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await coordinator.synchronize()

            #expect(result.applied == 100)
            #expect(try CollectionMockScenario.uploadedMangaIDs() == ids)
            #expect(try operations().isEmpty)
        }
    }
}
