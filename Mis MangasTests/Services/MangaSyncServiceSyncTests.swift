//
//  MangaSyncServiceSyncTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// One synchronization pass of `MangaSyncService`: the outbox drained oldest first through
    /// the real `CollectionRepository` (mocked transport, session scripted by `FakeSecurity`),
    /// then the server collection applied by the real `MangaSyncActor` on an in-memory store.
    /// Oracles: the requests captured by the mock (order, bodies, Bearer), the literal values of
    /// `collection_response.json`, and what a fresh `ModelContext` reads afterwards.
    @Suite("MangaSyncService — synchronization")
    struct MangaSyncServiceSyncTests {
        private static let token = "example.sync.token"
        private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

        private let actor: MangaSyncActor
        private let container: ModelContainer
        private let security: FakeSecurity
        private let changes: CallCounter
        private let service: MangaSyncService

        init() throws {
            CollectionMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            actor = made.actor
            container = made.container
            let security = FakeSecurity(token: Self.token, email: SessionTestTokenFactory.email)
            self.security = security
            let changes = CallCounter()
            self.changes = changes
            service = Self.makeService(
                actor: made.actor,
                collectionRepository: DefaultCollectionRepositoryTest(security: security),
                account: CollectionTestSupport.account
            ) {
                changes.increment()
            }
        }

        private static func makeService(
            actor: MangaSyncActor,
            collectionRepository: (any CollectionRepository)?,
            account: String?,
            onCollectionChanged: (@Sendable () -> Void)? = nil
        ) -> MangaSyncService {
            let mangaRepository = DefaultMangaRepositoryTest()
            return MangaSyncService(
                syncActor: actor,
                mangaRepository: mangaRepository,
                taxonomyCache: TaxonomyCacheActor(mangaRepository: mangaRepository),
                collectionRepository: collectionRepository,
                account: account,
                onCollectionChanged: onCollectionChanged
            )
        }

        /// Stores the mangas and queues one upsert per id, in the given order, one second apart, made
        /// under `account` (by default the account of the service).
        private func queueUpserts(_ ids: [Int], account: String? = CollectionTestSupport.account) async throws {
            try await CollectionTestSupport.storeMangas(ids, in: actor, now: Self.t0)
            for (offset, id) in ids.enumerated() {
                try await actor.saveCollectionEntry(
                    mangaID: id,
                    volumesOwned: [id],
                    readingVolume: nil,
                    completeCollection: false,
                    account: account,
                    now: Self.t0.addingTimeInterval(TimeInterval(offset + 1))
                )
            }
        }

        private func operations() throws -> [PendingOperation] {
            try CollectionTestSupport.operations(in: PersistenceTestSupport.freshContext(container))
        }

        // MARK: - Drain

        @Test func `A save makes no network call and the next pass uploads it with the Bearer token`() async throws {
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await service.saveCollectionEntry(mangaID: 1, volumesOwned: [2, 1], readingVolume: 2, completeCollection: false, account: CollectionTestSupport.account)
            #expect(CollectionMockScenario.totalHits() == 0)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await service.synchronizeCollection()

            #expect(result.applied == 1)
            #expect(try CollectionMockScenario.uploadedRequests() == [
                UserMangaCollectionRequest(manga: 1, completeCollection: false, volumesOwned: [1, 2], readingVolume: 2),
            ])
            #expect(CollectionMockScenario.lastRequest(.collectionUpsert)?.header("Authorization") == "Bearer \(Self.token)")
            #expect(try operations().isEmpty)
        }

        @Test func `A pass uploads the queue oldest first and then reads the server collection`() async throws {
            try await queueUpserts([3, 1, 2])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await service.synchronizeCollection()

            #expect(result.applied == 3)
            #expect(result.blocked == 0)
            #expect(result.rejected.isEmpty)
            #expect(try CollectionMockScenario.uploadedMangaIDs() == [3, 1, 2])
            #expect(CollectionMockScenario.arrivals() == [.collectionUpsert, .collectionUpsert, .collectionUpsert, .collectionList])
            #expect(try operations().isEmpty)
        }

        @Test(arguments: [
            (CatalogMockScenario.Behavior.status(503), "server"),
            (CatalogMockScenario.Behavior.status(500), "server"),
            (CatalogMockScenario.Behavior.transportError(.notConnectedToInternet), "transport"),
            (CatalogMockScenario.Behavior.transportError(.timedOut), "transport"),
        ])
        func `A retryable failure keeps the operation queued with only its error category`(failure: CatalogMockScenario.Behavior, category: String) async throws {
            try await queueUpserts([1])
            CollectionMockScenario.set(.collectionUpsert, failure)
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await service.synchronizeCollection()

            #expect(result.applied == 0)
            #expect(result.blocked == 0)
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 1)
            let operation = try #require(try operations().first)
            #expect(operation.attempts == 1)
            #expect(operation.lastError == category)
            #expect(operation.blockedAt == nil)
        }

        @Test func `An operation that fails with a 5xx three times is blocked on the third pass`() async throws {
            try await queueUpserts([1])
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 500, reason: "Something went wrong."))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            var blocked: [Int] = []
            for _ in 0..<3 {
                blocked.append(try await service.synchronizeCollection().blocked)
            }

            #expect(blocked == [0, 0, 1])
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 3)
            let operation = try #require(try operations().first)
            #expect(operation.attempts == 3)
            #expect(operation.blockedAt != nil)
            #expect(operation.lastError == "server")
        }

        @Test(arguments: [401, 403])
        func `A 401 or 403 on the second upload throws sessionExpired and leaves the rest of the queue untouched`(status: Int) async throws {
            try await queueUpserts([1, 2, 3])
            CollectionMockScenario.setSequence(.collectionUpsert, [.status(201), .status(status)])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            await expectSessionExpired {
                try await service.synchronizeCollection()
            }

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 2)
            #expect(CollectionMockScenario.hits(.collectionList) == 0)
            let remaining = try operations()
            #expect(remaining.map(\.mangaID) == [2, 3])
            #expect(remaining.map(\.attempts) == [0, 0])
            #expect(remaining.allSatisfy { $0.lastError == nil && $0.blockedAt == nil })
        }

        @Test func `A session without a token throws sessionExpired before touching the wire`() async throws {
            try await queueUpserts([1, 2])
            security.configure { $0.token = nil }

            await expectSessionExpired {
                try await service.synchronizeCollection()
            }

            #expect(CollectionMockScenario.totalHits() == 0)
            #expect(try operations().map(\.attempts) == [0, 0])
        }

        @Test func `A cancelled upload ends the pass without marking that operation or sending the next`() async throws {
            try await queueUpserts([1, 2, 3])
            CollectionMockScenario.setSequence(.collectionUpsert, [.status(201), .transportError(.cancelled)])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await service.synchronizeCollection()

            #expect(result.applied == 1)
            #expect(CollectionMockScenario.hits(.collectionList) == 0)
            #expect(changes.value == 0)
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 2)
            let remaining = try operations()
            #expect(remaining.map(\.mangaID) == [2, 3])
            #expect(remaining.map(\.attempts) == [0, 0])
            #expect(remaining.allSatisfy { $0.lastError == nil && $0.blockedAt == nil })
        }

        @Test func `An upload the server refuses with a 400 is discarded and reported as rejected`() async throws {
            try await queueUpserts([1, 2, 3])
            CollectionMockScenario.setSequence(.collectionUpsert, [
                .status(201),
                CollectionMockScenario.errorBody(status: 400, reason: "Bad request"),
                .status(201),
            ])
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await service.synchronizeCollection()

            #expect(result.applied == 2)
            #expect(result.rejected == [2])
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 3)
            #expect(try operations().isEmpty)
        }

        @Test func `A delete of an entry the server no longer has counts as applied`() async throws {
            try await queueUpserts([7])
            try await actor.removeCollectionEntry(mangaID: 7, account: CollectionTestSupport.account, now: Self.t0.addingTimeInterval(10))
            CollectionMockScenario.set(.collectionDelete, CollectionMockScenario.errorBody(status: 404, reason: "This manga is not at user collection."))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await service.synchronizeCollection()

            #expect(result.applied == 1)
            #expect(result.rejected.isEmpty)
            #expect(CollectionMockScenario.deletedMangaIDs() == [7])
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)
            #expect(CollectionMockScenario.lastRequest(.collectionDelete)?.header("Authorization") == "Bearer \(Self.token)")
            #expect(try operations().isEmpty)
        }

        @Test func `A pass never uploads the queue of another account, and uploads the guest's as its own`() async throws {
            try await queueUpserts([1], account: CollectionTestSupport.otherAccount)
            try await queueUpserts([2], account: nil)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await service.synchronizeCollection()

            #expect(result.applied == 1)
            #expect(try CollectionMockScenario.uploadedMangaIDs() == [2])
            #expect(CollectionMockScenario.hits(.collectionList) == 1)
            // The other account's upload is gone for good: no later pass of this account sends it.
            #expect(try operations().isEmpty)
        }

        // MARK: - Snapshot

        @Test func `The server collection creates its entries and removes a local one it no longer has`() async throws {
            let berserk = try #require(try CollectionTestSupport.remoteCollection().last)
            try await actor.upsertCollectionEntry(from: berserk.replacing(mangaID: 50), now: Self.t0)
            CollectionMockScenario.set(.collectionList, .fixture("collection_response.json"))

            let result = try await service.synchronizeCollection()

            #expect(result.upserted == 2)
            #expect(result.removed == 1)
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try CollectionTestSupport.entries(in: context).map(\.mangaID) == [1, 2])
            #expect(try PersistenceTestSupport.manga(id: 2, in: context)?.title == "Berserk")
            let removed = try #require(try PersistenceTestSupport.manga(id: 50, in: context))
            #expect(!removed.inCollection)
        }

        @Test func `The server collection never overwrites nor removes an entry whose operation is still queued`() async throws {
            // Monster (1) is on the server with other values; 99 is not on the server at all.
            try await queueUpserts([1, 99])
            CollectionMockScenario.set(.collectionUpsert, .status(503))
            CollectionMockScenario.set(.collectionList, .fixture("collection_response.json"))

            let result = try await service.synchronizeCollection()

            #expect(result.upserted == 1)
            #expect(result.removed == 0)
            let context = PersistenceTestSupport.freshContext(container)
            let entries = try CollectionTestSupport.entries(in: context)
            #expect(entries.map(\.mangaID) == [1, 2, 99])
            #expect(entries.map(\.volumesOwned) == [[1], [1, 2, 3], [99]])
            #expect(try CollectionTestSupport.operations(in: context).map(\.mangaID) == [1, 99])
        }

        @Test func `A server collection equal to the stored one keeps every updatedAt`() async throws {
            for dto in try CollectionTestSupport.remoteCollection() {
                try await actor.upsertCollectionEntry(from: dto, now: Self.t0)
            }
            CollectionMockScenario.set(.collectionList, .fixture("collection_response.json"))

            _ = try await service.synchronizeCollection()

            let context = PersistenceTestSupport.freshContext(container)
            #expect(try CollectionTestSupport.entries(in: context).map(\.updatedAt) == [Self.t0, Self.t0])
            #expect(CollectionMockScenario.hits(.collectionList) == 1)
        }

        // MARK: - Pass bookkeeping

        @Test func `onCollectionChanged is called once per pass`() async throws {
            try await queueUpserts([1, 2])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, .fixture("collection_response.json"))

            _ = try await service.synchronizeCollection()
            #expect(changes.value == 1)

            _ = try await service.synchronizeCollection()
            #expect(changes.value == 2)
        }

        @Test func `A guest pass returns an empty result without network and keeps the queue`() async throws {
            try await queueUpserts([1])
            let guest = Self.makeService(actor: actor, collectionRepository: nil, account: nil)

            let result = try await guest.synchronizeCollection()

            #expect(result.applied == 0)
            #expect(result.blocked == 0)
            #expect(result.rejected.isEmpty)
            #expect(result.upserted == 0)
            #expect(result.removed == 0)
            #expect(CollectionMockScenario.totalHits() == 0)
            let operation = try #require(try operations().first)
            #expect(operation.mangaID == 1)
            #expect(operation.attempts == 0)
        }
    }
}
