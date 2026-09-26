//
//  CollectionViewModelSyncTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 25/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Observation
import SwiftData
import Testing

extension SharedMockSuites {
    /// The collection's synchronization as the screens drive it: `CollectionViewModel` over the
    /// device-only `MangaSyncService` the views get, the app's `SyncCoordinator`, and a real
    /// `SessionViewModel` whose account backend is a `FakeSecurity`. Signing in hands the coordinator
    /// a service of that account whose repository reaches the mocked transport, as the app does
    /// when the session changes.
    ///
    /// Oracles: the requests the mock received (count, order and bodies), the literal values of
    /// `collection_response.json`, the clock read around each pass, and the outbox a fresh
    /// `ModelContext` reads afterwards.
    ///
    /// A class only for `deinit`, which removes the `UserDefaults` suite of the session.
    @Suite("CollectionViewModel — synchronization")
    @MainActor
    final class CollectionViewModelSyncTests {
        private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        private static let t1 = Date(timeIntervalSinceReferenceDate: 800_000_100)
        /// Any eight characters: the account backend is a `FakeSecurity` that accepts them.
        private static let longEnough = "12345678"

        private let suiteName: String
        private let actor: MangaSyncActor
        private let container: ModelContainer
        private let security: FakeSecurity
        /// The service the screens get: every write stays on the device and queues its upload.
        private let deviceService: MangaSyncService
        private let coordinator: SyncCoordinator
        private let session: SessionViewModel
        private let viewModel: CollectionViewModel

        init() throws {
            CollectionMockScenario.reset()
            let suiteName = "CollectionViewModelSyncTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            let made = try PersistenceTestSupport.makeActor()
            let actor = made.actor
            let security = FakeSecurity()
            let deviceService = CollectionTestSupport.makeService(actor: actor, account: nil, security: security)
            let coordinator = SyncCoordinator(service: deviceService)
            let session = SessionViewModel(
                security: security,
                syncCoordinator: coordinator,
                syncActor: actor,
                defaults: defaults,
                makeSyncService: { account in
                    CollectionTestSupport.makeService(actor: actor, account: account, security: security)
                }
            )
            self.suiteName = suiteName
            self.actor = actor
            container = made.container
            self.security = security
            self.deviceService = deviceService
            self.coordinator = coordinator
            self.session = session
            viewModel = CollectionViewModel(syncService: deviceService, syncCoordinator: coordinator, session: session)
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        /// Signs in and hands the coordinator the service of that account.
        private func signIn() async throws {
            await session.signIn(email: CollectionTestSupport.account, password: Self.longEnough)
            try #require(session.isAuthenticated)
            await coordinator.replaceService(
                CollectionTestSupport.makeService(actor: actor, account: CollectionTestSupport.account, security: security)
            )
        }

        /// Queues an upsert of `mangaID` made under `account`, straight through the actor.
        private func queueSave(_ mangaID: Int, account: String?) async throws {
            try await actor.saveCollectionEntry(
                mangaID: mangaID,
                volumesOwned: [1],
                readingVolume: nil,
                completeCollection: false,
                account: account,
                now: Self.t1
            )
        }

        private func operations() throws -> [PendingOperation] {
            try CollectionTestSupport.operations(in: PersistenceTestSupport.freshContext(container))
        }

        // MARK: - Writes ask for a pass

        @Test(.timeLimit(.minutes(1)))
        func `save with a connection asks for a pass that uploads it, and afterwards nothing is pending`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            await viewModel.save(mangaID: 1, volumesOwned: [2, 1], readingVolume: 2, completeCollection: false)
            // Nobody but the save asked for a pass: the upload in flight is its pass.
            try #require(await CollectionMockScenario.waitUntilHeldOrCancelled(.collectionUpsert))
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            // Joins that pass (or runs one more over an empty queue) and waits for it.
            await viewModel.synchronize()
            await viewModel.refreshCounts()

            #expect(try CollectionMockScenario.uploadedRequests() == [
                UserMangaCollectionRequest(manga: 1, completeCollection: false, volumesOwned: [1, 2], readingVolume: 2),
            ])
            #expect(viewModel.pendingCount == 0)
            #expect(viewModel.blockedCount == 0)
            #expect(try operations().isEmpty)
        }

        @Test(.timeLimit(.minutes(1)))
        func `remove with a connection asks for a pass that deletes the entry on the server`() async throws {
            try await signIn()
            let monster = try #require(try CollectionTestSupport.remoteCollection().first)
            try await actor.upsertCollectionEntry(from: monster, now: Self.t0)
            CollectionMockScenario.setSequence(.collectionDelete, [.held])
            CollectionMockScenario.set(.collectionDelete, .status(200))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            await viewModel.remove(mangaID: 1)
            try #require(await CollectionMockScenario.waitUntilHeldOrCancelled(.collectionDelete))
            CatalogMockScenario.release(.collectionDelete, with: .status(200))
            await viewModel.synchronize()

            #expect(CollectionMockScenario.deletedMangaIDs() == [1])
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)
            #expect(try operations().isEmpty)
        }

        @Test func `save without a connection leaves the change pending, not blocked`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionUpsert, .transportError(.notConnectedToInternet))
            CollectionMockScenario.set(.collectionList, .transportError(.notConnectedToInternet))

            await viewModel.save(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false)
            // Waits for the pass the save asked for, or runs one.
            await viewModel.synchronize()
            await viewModel.refreshCounts()

            #expect(CollectionMockScenario.hits(.collectionUpsert) >= 1)
            #expect(viewModel.pendingCount == 1)
            #expect(viewModel.blockedCount == 0)
            #expect(try operations().map(\.mangaID) == [1])
        }

        @Test func `save and remove stamp on their queued operation the account of the session at that moment`() async throws {
            // Typed with capitals: the account is the address in lowercase.
            await session.signIn(email: "Reader@Example.com", password: Self.longEnough)
            try #require(session.isAuthenticated)
            // The coordinator keeps the device-only service, so no pass takes anything off the queue.
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)

            await viewModel.save(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false)
            await session.expire()
            try #require(!session.isAuthenticated)
            await viewModel.remove(mangaID: 2)

            let operations = try CollectionTestSupport.operationsByManga(in: PersistenceTestSupport.freshContext(container))
            #expect(operations.map(\.mangaID) == [1, 2])
            #expect(operations.map(\.operationType) == ["upsert", "delete"])
            #expect(operations.map(\.account) == [CollectionTestSupport.account, nil])
        }

        // MARK: - Counters

        @Test func `refreshCounts counts the pending and blocked changes of the session's account and the guest's, never another account's`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1, 2, 3, 4], in: actor, now: Self.t0)
            try await queueSave(1, account: CollectionTestSupport.otherAccount)
            try await queueSave(2, account: nil)
            try await queueSave(3, account: CollectionTestSupport.account)
            try await queueSave(4, account: CollectionTestSupport.account)
            try await CollectionTestSupport.block(mangaID: 4, in: actor, container: container, now: Self.t1)

            await viewModel.refreshCounts()

            #expect(viewModel.pendingCount == 2)
            #expect(viewModel.blockedCount == 1)
        }

        // MARK: - synchronize

        @Test func `synchronize seals lastSyncDate and lastResult, and isSyncing is true only while the pass runs`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueSave(1, account: CollectionTestSupport.account)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.setSequence(.collectionList, [.held])
            let viewModel = viewModel
            #expect(!viewModel.isSyncing)

            let before = Date.now
            let syncing = Task { await viewModel.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionList, orUntilFinished: syncing))
            #expect(viewModel.isSyncing)
            CatalogMockScenario.release(.collectionList, with: .fixture("collection_response.json"))
            await syncing.value
            let after = Date.now

            #expect(!viewModel.isSyncing)
            let date = try #require(viewModel.lastSyncDate)
            #expect((before ... after).contains(date))
            let result = try #require(viewModel.lastResult)
            #expect(result.applied == 1)
            // Monster changed from what was saved and Berserk is new: both entries of the fixture.
            #expect(result.upserted == 2)
            #expect(result.rejected.isEmpty)
        }

        @Test func `synchronize that ends in sessionExpired keeps the last result, stops syncing and leaves the session alone`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            try await queueSave(1, account: CollectionTestSupport.account)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            await viewModel.synchronize()
            let sealedDate = try #require(viewModel.lastSyncDate)
            try #require(viewModel.lastResult?.applied == 1)
            try await queueSave(2, account: CollectionTestSupport.account)
            CollectionMockScenario.set(.collectionUpsert, .status(401))

            await viewModel.synchronize()

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 2)
            #expect(!viewModel.isSyncing)
            #expect(viewModel.lastSyncDate == sealedDate)
            #expect(viewModel.lastResult?.applied == 1)
            // Ending the session is the job of the one consumer of the coordinator's events.
            #expect(session.isAuthenticated)
            #expect(security.calls(.clearToken) == 0)
        }

        @Test func `A second CollectionViewModel over the same coordinator shows the same last pass after refreshCounts`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueSave(1, account: CollectionTestSupport.account)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            await viewModel.synchronize()
            let sealedDate = try #require(viewModel.lastSyncDate)

            let other = CollectionViewModel(syncService: deviceService, syncCoordinator: coordinator, session: session)
            await other.refreshCounts()

            #expect(other.lastSyncDate == sealedDate)
            #expect(other.lastResult?.applied == 1)
            #expect(CollectionMockScenario.hits(.collectionList) == 1)
        }

        // MARK: - retryBlocked

        @Test func `retryBlocked gives the blocked changes another chance and sends them`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueSave(1, account: CollectionTestSupport.account)
            try await CollectionTestSupport.block(mangaID: 1, in: actor, container: container, now: Self.t1)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            await viewModel.refreshCounts()
            try #require(viewModel.blockedCount == 1)

            await viewModel.retryBlocked()
            await viewModel.refreshCounts()

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1])
            #expect(viewModel.lastResult?.applied == 1)
            #expect(viewModel.pendingCount == 0)
            #expect(viewModel.blockedCount == 0)
            #expect(try operations().isEmpty)
        }

        // MARK: - Rejected changes

        @Test func `A change the server rejects with a 400 is reported in lastResult and the entry takes the server's values`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueSave(1, account: CollectionTestSupport.account)
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            CollectionMockScenario.set(.collectionList, .fixture("collection_response.json"))

            await viewModel.synchronize()

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1])
            #expect(viewModel.lastResult?.rejected == [1])
            let context = PersistenceTestSupport.freshContext(container)
            let monster = try #require(try CollectionTestSupport.entry(mangaID: 1, in: context))
            #expect(monster.volumesOwned == Array(1 ... 18))
            #expect(monster.readingVolume == 12)
            #expect(monster.completeCollection)
            #expect(try CollectionTestSupport.operations(in: context).isEmpty)
        }

        // MARK: - Passes asked for elsewhere

        /// Starts watching whatever `read` reads on the view model and returns a stream that yields
        /// once, at its next change. The observation is registered before this returns, so a change
        /// made afterwards is never missed; iterating it ends when the test is cancelled (its time limit).
        private func nextChange(of read: () -> Void) -> AsyncStream<Void> {
            let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
            withObservationTracking {
                read()
            } onChange: {
                continuation.yield()
                continuation.finish()
            }
            return stream
        }

        @Test(.timeLimit(.minutes(1)))
        func `observePasses reads the queue and the last pass again when a pass someone else asked for ends`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            try await queueSave(1, account: CollectionTestSupport.account)
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            await coordinator.requestSync()
            try #require(await CollectionMockScenario.waitUntilHeldOrCancelled(.collectionUpsert))
            let viewModel = viewModel

            // Its first reading, taken once it listens, shows the change still waiting.
            let subscribed = nextChange { _ = viewModel.pendingCount }
            let observing = Task { await viewModel.observePasses() }
            defer { observing.cancel() }
            for await _ in subscribed {}
            try #require(viewModel.pendingCount == 1)
            try #require(viewModel.lastSyncDate == nil)

            // The pass the screen never asked for ends: the screen shows what it left.
            let refreshed = nextChange { _ = viewModel.lastSyncDate }
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            for await _ in refreshed {}

            #expect(viewModel.pendingCount == 0)
            #expect(viewModel.lastSyncDate != nil)
            #expect(viewModel.lastResult?.applied == 1)
        }

        @Test func `Refused changes bring up the notice until it is acknowledged, and the next refusals bring it up again`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            #expect(!viewModel.isRejectionNoticePresented)

            try await queueSave(1, account: CollectionTestSupport.account)
            await viewModel.synchronize()
            #expect(viewModel.isRejectionNoticePresented)
            #expect(viewModel.rejectedMangaIDs == [1])

            await viewModel.acknowledgeRejections()
            #expect(!viewModel.isRejectionNoticePresented)
            #expect(viewModel.rejectedMangaIDs.isEmpty)
            #expect(try await coordinator.status().rejections.isEmpty)
            // A pass that refuses nothing leaves the notice down.
            await viewModel.synchronize()
            #expect(!viewModel.isRejectionNoticePresented)

            try await queueSave(2, account: CollectionTestSupport.account)
            await viewModel.synchronize()
            #expect(viewModel.isRejectionNoticePresented)
            #expect(viewModel.rejectedMangaIDs == [2])
        }

        // MARK: - What the screen offers and announces

        @Test func `Syncing is offered while signed in and not as a guest`() async throws {
            #expect(!viewModel.isSyncAvailable)
            try await signIn()
            #expect(viewModel.isSyncAvailable)
            session.continueAsGuest()
            #expect(!viewModel.isSyncAvailable)
        }

        @Test func `The outcome of a sync says whether everything went up, what still waits and what was set aside`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            try await queueSave(1, account: CollectionTestSupport.account)
            CollectionMockScenario.set(.collectionUpsert, .transportError(.notConnectedToInternet))
            await viewModel.synchronize()
            #expect(viewModel.syncOutcome == .waiting(1))

            try await CollectionTestSupport.block(mangaID: 1, in: actor, container: container, now: Self.t1)
            await viewModel.refreshCounts()
            #expect(viewModel.syncOutcome == .blocked(1))

            CollectionMockScenario.set(.collectionUpsert, .status(201))
            await viewModel.retryBlocked()
            #expect(viewModel.syncOutcome == .allSynced)
        }
    
        @Test func `Acknowledging the notice keeps a refusal that arrived after it was read, and brings the notice back for it`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await queueSave(1, account: CollectionTestSupport.account)
            await viewModel.synchronize()
            try #require(viewModel.rejectedMangaIDs == [1])
            // A pass the screen has not read yet refuses another change.
            try await queueSave(2, account: CollectionTestSupport.account)
            _ = try await coordinator.synchronize()

            await viewModel.acknowledgeRejections()

            #expect(viewModel.rejectedMangaIDs == [2])
            #expect(viewModel.isRejectionNoticePresented)
        }

        @Test func `A sync the user asked for is announced unless an alert already tells what happened`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            await viewModel.synchronize()
            #expect(viewModel.syncAnnouncement == SyncOutcome.allSynced.announcement)

            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            try await queueSave(1, account: CollectionTestSupport.account)
            await viewModel.synchronize()
            try #require(viewModel.isRejectionNoticePresented)
            #expect(viewModel.syncAnnouncement == nil)
        }
    
        @Test func `A screen without the refusal notice never raises it, so its sync is still announced`() async throws {
            try await signIn()
            try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 400, reason: "Bad request"))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await queueSave(1, account: CollectionTestSupport.account)
            let profile = CollectionViewModel(
                syncService: deviceService,
                syncCoordinator: coordinator,
                session: session,
                presentsRejections: false
            )

            await profile.synchronize()

            #expect(profile.rejectedMangaIDs == [1])
            #expect(!profile.isRejectionNoticePresented)
            #expect(profile.syncAnnouncement == SyncOutcome.allSynced.announcement)
        }
    }
}
