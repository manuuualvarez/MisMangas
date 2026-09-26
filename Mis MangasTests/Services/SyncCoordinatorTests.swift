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
                collectionRepository: DefaultCollectionRepositoryTest(security: FakeSecurity(token: "example.coordinator.token")),
                account: CollectionTestSupport.account
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
                account: CollectionTestSupport.account,
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
                try await service.saveCollectionEntry(mangaID: id, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: CollectionTestSupport.account)
            }
            #expect(CollectionMockScenario.totalHits() == 0)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            let result = try await coordinator.synchronize()

            #expect(result.applied == 100)
            #expect(try CollectionMockScenario.uploadedMangaIDs() == ids)
            #expect(try operations().isEmpty)
        }

        // MARK: - replaceService

        /// Token presented by the service built in `init`.
        private static let originalToken = "example.coordinator.token"
        /// Token presented by the service that replaces it.
        private static let replacementToken = "example.replacement.token"

        /// A service over the same store whose repository presents `token`, so every request it
        /// sends carries `Bearer <token>` and tells it apart from the service built in `init`.
        private func service(presenting token: String) -> MangaSyncService {
            let mangaRepository = DefaultMangaRepositoryTest()
            return MangaSyncService(
                syncActor: actor,
                mangaRepository: mangaRepository,
                taxonomyCache: TaxonomyCacheActor(mangaRepository: mangaRepository),
                collectionRepository: DefaultCollectionRepositoryTest(security: FakeSecurity(token: token)),
                account: CollectionTestSupport.account
            )
        }

        @Test func `replaceService stops the pass in flight, and the next synchronize reaches the server only through the new service`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let coordinator = coordinator

            let caller = Task { try await coordinator.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: caller))
            await coordinator.replaceService(service(presenting: Self.replacementToken))
            // A pass that was not stopped would carry on from here and upload the rest.
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            _ = await caller.result

            #expect(CollectionMockScenario.totalHits() == 1)

            let result = try await coordinator.synchronize()

            #expect(result.applied == 2)
            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1, 1, 2])
            let original = "Bearer \(Self.originalToken)"
            let replacement = "Bearer \(Self.replacementToken)"
            #expect(CollectionMockScenario.requests(.collectionUpsert).map { $0.header("Authorization") } == [original, replacement, replacement])
            #expect(CollectionMockScenario.requests(.collectionList).map { $0.header("Authorization") } == [replacement])
            #expect(try operations().isEmpty)
        }

        // MARK: - Last pass and events

        @Test func `lastSyncDate and lastResult are sealed by a pass that succeeds and left as they were by one that ends in sessionExpired`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            #expect(try await coordinator.status().lastSyncDate == nil)
            #expect(try await coordinator.status().lastResult == nil)

            let before = Date.now
            _ = try await coordinator.synchronize()
            let after = Date.now

            let sealedDate = try #require(try await coordinator.status().lastSyncDate)
            #expect((before ... after).contains(sealedDate))
            #expect(try await coordinator.status().lastResult?.applied == 1)

            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            CollectionMockScenario.set(.collectionUpsert, .status(401))
            await expectSessionExpired {
                try await coordinator.synchronize()
            }

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 2)
            #expect(try await coordinator.status().lastSyncDate == sealedDate)
            #expect(try await coordinator.status().lastResult?.applied == 1)
        }

        @Test(.timeLimit(.minutes(1)))
        func `events emits sessionExpired once for each pass that ends that way, whether requestSync or synchronize asked for it`() async throws {
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            // Every upload waits for the test; a 401 leaves the operation queued for the next pass.
            CollectionMockScenario.set(.collectionUpsert, .held)
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let coordinator = coordinator
            let recorder = SyncEventRecorder()
            let consumer = recorder.consume(await coordinator.events())
            defer { consumer.cancel() }

            // Phase 1: a pass nobody waits for.
            await coordinator.requestSync()
            try #require(await CollectionMockScenario.waitUntilHeldOrCancelled(.collectionUpsert))
            recorder.enter(1)
            CatalogMockScenario.release(.collectionUpsert, with: .status(401))
            await recorder.waitUntilReceived(1)

            // Phase 2: a pass a caller waits for. An event emitted twice in phase 1 would be recorded
            // before the test gets here.
            let caller = Task { try await coordinator.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: caller))
            recorder.enter(2)
            CatalogMockScenario.release(.collectionUpsert, with: .status(401))
            await expectSessionExpired {
                try await caller.value
            }
            await recorder.waitUntilReceived(2)

            #expect(recorder.phases == [1, 2])
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 2)
            #expect(try operations().map(\.mangaID) == [1])
        }

        @Test(.timeLimit(.minutes(1)))
        func `A subscriber that stops listening leaves the others subscribed`() async throws {
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            CollectionMockScenario.set(.collectionUpsert, .status(401))
            let leaving = SyncEventRecorder()
            let leavingConsumer = leaving.consume(await coordinator.events())
            let staying = SyncEventRecorder()
            let stayingConsumer = staying.consume(await coordinator.events())
            defer { stayingConsumer.cancel() }
            leavingConsumer.cancel()
            await leavingConsumer.value

            await expectSessionExpired {
                try await coordinator.synchronize()
            }
            await staying.waitUntilReceived(1)

            #expect(staying.phases == [0])
            #expect(leaving.phases.isEmpty)
        }

        // MARK: - Refused changes

        @Test func `The changes the server refuses add up across passes until they are acknowledged`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            _ = try await coordinator.synchronize()
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)

            let last = try await coordinator.synchronize()

            #expect(last.rejected == [2])
            #expect(try await coordinator.status().rejections == [1, 2])
            await coordinator.acknowledgeRejections([1, 2])
            #expect(try await coordinator.status().rejections.isEmpty)
        }

        // MARK: - Session changes and finished passes

        @Test(.timeLimit(.minutes(1)))
        func `replaceService forgets the last pass and the refusals of the previous session`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2, 3], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            _ = try await coordinator.synchronize()
            try #require(try await coordinator.status().lastSyncDate != nil)
            try #require(try await coordinator.status().rejections == [1])

            await coordinator.replaceService(service)

            #expect(try await coordinator.status().lastSyncDate == nil)
            #expect(try await coordinator.status().lastResult == nil)
            #expect(try await coordinator.status().rejections.isEmpty)
        }

        @Test(.timeLimit(.minutes(1)))
        func `passFinished comes once for every pass that ends, whatever its outcome, and is not kept for a later subscriber`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            let early = SyncEventRecorder(recording: .passFinished)
            let earlyConsumer = early.consume(await coordinator.events())

            early.enter(1)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            _ = try await coordinator.synchronize()
            await early.waitUntilReceived(1)
            early.enter(2)
            CollectionMockScenario.set(.collectionUpsert, .status(401))
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            await expectSessionExpired {
                try await coordinator.synchronize()
            }
            await early.waitUntilReceived(2)
            earlyConsumer.cancel()
            await earlyConsumer.value
            #expect(early.phases == [1, 2])

            // A pass that ends while nobody listens leaves nothing for the next subscriber.
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            _ = try await coordinator.synchronize()
            let late = SyncEventRecorder(recording: .passFinished)
            let lateConsumer = late.consume(await coordinator.events())
            defer { lateConsumer.cancel() }
            late.enter(3)
            _ = try await coordinator.synchronize()
            await late.waitUntilReceived(1)
            #expect(late.phases == [3])
        }

        @Test(.timeLimit(.minutes(1)))
        func `A pass stopped while it ends in sessionExpired publishes nothing to the listeners of the next session`() async throws {
            let coordinator = coordinator
            let service = service
            let stubborn = StubbornCollectionRepository(security: FakeSecurity(token: "example.stopped.token"))
            let mangaRepository = DefaultMangaRepositoryTest()
            let stoppedService = MangaSyncService(
                syncActor: actor,
                mangaRepository: mangaRepository,
                taxonomyCache: TaxonomyCacheActor(mangaRepository: mangaRepository),
                collectionRepository: stubborn,
                account: CollectionTestSupport.account
            )
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            await coordinator.replaceService(stoppedService)
            let recorder = SyncEventRecorder(recording: nil)
            let consumer = recorder.consume(await coordinator.events())
            defer { consumer.cancel() }

            await coordinator.requestSync()
            await stubborn.waitUntilHeld()
            // The session changes while the upload waits; the server's 401 arrives after the pass was stopped.
            let replacing = Task { _ = await coordinator.replaceService(service) }
            await stubborn.waitUntilCancelled()
            stubborn.release(throwing: .unauthorized)
            await replacing.value

            // A subscription delivers in order: anything the stopped pass published would come first.
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            _ = try await coordinator.synchronize()
            await recorder.waitUntilReceived(1)
            #expect(recorder.events == [.passFinished])
        }

        @Test func `status gathers the queue of the service's account, the last pass and the refusals`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2, 3], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            _ = try await coordinator.synchronize()
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            try await actor.saveCollectionEntry(
                mangaID: 3,
                volumesOwned: [1],
                readingVolume: nil,
                completeCollection: false,
                account: CollectionTestSupport.otherAccount,
                now: Self.t0.addingTimeInterval(3)
            )

            let status = try await coordinator.status()

            #expect(status.pendingCount == 1)
            #expect(status.blockedCount == 0)
            #expect(status.lastSyncDate != nil)
            #expect(status.lastResult?.rejected == [1])
            #expect(status.rejections == [1])
        }

        @Test func `acknowledgeRejections forgets only the refusals that were shown`() async throws {
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            _ = try await coordinator.synchronize()
            let shown = try await coordinator.status().rejections
            // Another refusal arrives before the notice is dismissed.
            try await queueUpsert(mangaID: 2, secondsAfterStart: 2)
            _ = try await coordinator.synchronize()

            await coordinator.acknowledgeRejections(shown)

            #expect(try await coordinator.status().rejections == [2])
        }

        @Test func `retryBlocked gives the blocked changes of the queue another chance and sends them`() async throws {
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            try await CollectionTestSupport.block(mangaID: 1, in: actor, container: container, now: Self.t0.addingTimeInterval(2))
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try #require(try await coordinator.status().blockedCount == 1)

            let result = try await coordinator.retryBlocked()

            #expect(result.applied == 1)
            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1])
            #expect(try await coordinator.status().blockedCount == 0)
            #expect(try operations().isEmpty)
        }
    
        @Test(.timeLimit(.minutes(1)))
        func `replaceService hands back a subscription that hears the passes of the new session`() async throws {
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueUpsert(mangaID: 1, secondsAfterStart: 1)
            CollectionMockScenario.set(.collectionUpsert, .status(401))
            let recorder = SyncEventRecorder(recording: nil)

            let consumer = recorder.consume(await coordinator.replaceService(service))
            defer { consumer.cancel() }
            await expectSessionExpired {
                try await coordinator.synchronize()
            }
            await recorder.waitUntilReceived(2)

            #expect(recorder.events == [.sessionExpired, .passFinished])
        }
    }
}
