//
//  WatchSyncServiceTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// `WatchSyncService` over the real `MangaSyncActor` (in-memory store) and a real
    /// `SyncCoordinator` whose `MangaSyncService` reaches the collection through the mocked
    /// transport; the watch is a `FakeWatchTransport`. The service runs on its own task, so every
    /// effect is awaited with a bounded wait. Oracles: the snapshots the fake received, compared
    /// with values written by hand, the uploads captured by the mock and what a fresh
    /// `ModelContext` reads.
    @Suite("WatchSyncService")
    struct WatchSyncServiceTests {
        private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        private static let token = "example.watch.token"
        private static let dragonBallCover = "https://cdn.myanimelist.net/images/manga/1/267793l.jpg"
        /// A moment after the seeded entry's last change, with a fraction so a rounded date would show.
        private static let later = t0.addingTimeInterval(60.125)

        private let actor: MangaSyncActor
        private let container: ModelContainer
        private let transport = FakeWatchTransport()

        init() throws {
            CollectionMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            actor = made.actor
            container = made.container
        }

        /// The service and the coordinator it follows. With an account the passes reach the server
        /// through the mock; without one they are the guest's and stay on the device.
        private func makeWatchSync(account: String?, isSignedOut: Bool = false) -> (watchSync: WatchSyncService, coordinator: SyncCoordinator) {
            let service = CollectionTestSupport.makeService(actor: actor, account: account, security: FakeSecurity(token: Self.token))
            let coordinator = SyncCoordinator(service: service)
            let watchSync = WatchSyncService(
                transport: transport,
                syncActor: actor,
                syncCoordinator: coordinator,
                sessionState: { (account: account, isSignedOut: isSignedOut) }
            )
            return (watchSync, coordinator)
        }

        // MARK: - Seeds and expected items

        /// Dragon Ball in the collection, reading volume 7 of 42, entry last changed at `t0`.
        private func seedDragonBall() throws {
            try ReadingListTestSupport.insertManga(
                id: 42,
                title: "Dragon Ball",
                volumes: 42,
                coverURL: Self.dragonBallCover,
                updatedAt: Self.t0.addingTimeInterval(-100),
                entry: ReadingListTestSupport.Entry(readingVolume: 7, volumesOwned: [1, 2, 3], updatedAt: Self.t0),
                in: container
            )
        }

        /// Dragon Ball as the watch must receive it, reading `readingVolume` since `updatedAt`.
        private static func dragonBall(readingVolume: Int, updatedAt: Date) -> ReadingItem {
            ReadingItem(
                mangaID: 42,
                title: "Dragon Ball",
                coverURL: dragonBallCover,
                readingVolume: readingVolume,
                volumes: 42,
                completeCollection: false,
                updatedAt: updatedAt
            )
        }

        /// Dragon Ball and Monster being read (Monster changed later) and a complete collection
        /// that is not being read.
        private func seedReadingList() throws {
            try seedDragonBall()
            try ReadingListTestSupport.insertManga(
                id: 1,
                title: "Monster",
                volumes: 18,
                coverURL: nil,
                updatedAt: Self.t0.addingTimeInterval(-200),
                entry: ReadingListTestSupport.Entry(readingVolume: 3, updatedAt: Self.t0.addingTimeInterval(30)),
                in: container
            )
            try ReadingListTestSupport.insertManga(
                id: 4,
                volumes: 7,
                updatedAt: Self.t0,
                entry: ReadingListTestSupport.Entry(readingVolume: 7, completeCollection: true, updatedAt: Self.t0.addingTimeInterval(40)),
                in: container
            )
        }

        /// The items of `seedReadingList()`, most recently changed first.
        private static let readingListItems = [
            ReadingItem(
                mangaID: 1,
                title: "Monster",
                coverURL: nil,
                readingVolume: 3,
                volumes: 18,
                completeCollection: false,
                updatedAt: t0.addingTimeInterval(30)
            ),
            dragonBall(readingVolume: 7, updatedAt: t0),
        ]

        private func storedEntry(mangaID: Int) throws -> UserCollectionEntry? {
            try CollectionTestSupport.entry(mangaID: mangaID, in: PersistenceTestSupport.freshContext(container))
        }

        private func operations() throws -> [PendingOperation] {
            try CollectionTestSupport.operations(in: PersistenceTestSupport.freshContext(container))
        }

        // MARK: - Activation

        @Test(.timeLimit(.minutes(1)))
        func `start activates the session once and publishes the reading list when it activates`() async throws {
            try seedReadingList()
            let (watchSync, _) = makeWatchSync(account: nil)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }

            try #require(await AsyncCondition.waitUntil { transport.activateCalls == 1 })
            transport.emit(.activated(isReachable: true))
            try #require(await AsyncCondition.waitUntil { !transport.publishedSnapshots.isEmpty })

            #expect(transport.activateCalls == 1)
            #expect(transport.publishedSnapshots.map(\.items) == [Self.readingListItems])
        }

        @Test(.timeLimit(.minutes(1)))
        func `The service keeps listening after the task that started it is cancelled, and a second start does not activate again`() async throws {
            try seedReadingList()
            let (watchSync, _) = makeWatchSync(account: nil)
            defer { transport.finish() }
            let starting = Task { await watchSync.start() }
            try #require(await AsyncCondition.waitUntil { transport.activateCalls == 1 })

            starting.cancel()
            await starting.value
            // Returns at once: the listening started by the first call goes on.
            await watchSync.start()
            transport.emit(.activated(isReachable: true))

            try #require(await AsyncCondition.waitUntil { !transport.publishedSnapshots.isEmpty })
            #expect(transport.activateCalls == 1)
            #expect(transport.publishedSnapshots.map(\.items) == [Self.readingListItems])
        }

        // MARK: - Updates from the watch

        @Test(.timeLimit(.minutes(1)))
        func `A later update is applied, queued under the session's account, uploaded by a pass and republished`() async throws {
            try seedDragonBall()
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            // Unanswered server collection: the pass keeps the entry as the watch left it.
            CollectionMockScenario.set(.collectionList, .status(503))
            let (watchSync, coordinator) = makeWatchSync(account: CollectionTestSupport.account)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }

            transport.emit(.readingUpdate(ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: Self.later)))
            // Nobody but the update asked for a pass: the upload in flight is its pass.
            try #require(await AsyncCondition.waitUntil { CollectionMockScenario.hits(.collectionUpsert) == 1 })

            let entry = try #require(try storedEntry(mangaID: 42))
            #expect(entry.readingVolume == 8)
            #expect(entry.updatedAt == Self.later)
            let queued = try operations()
            try #require(queued.count == 1)
            #expect(queued[0].mangaID == 42)
            #expect(queued[0].operationType == PendingOperationType.upsert.rawValue)
            #expect(queued[0].account == CollectionTestSupport.account)

            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            let expected = [Self.dragonBall(readingVolume: 8, updatedAt: Self.later)]
            try #require(await AsyncCondition.waitUntil { transport.publishedSnapshots.last?.items == expected })
            // Joins the pass still running, if any, and waits for it.
            _ = try await coordinator.synchronize()

            #expect(try CollectionMockScenario.uploadedRequests() == [
                UserMangaCollectionRequest(manga: 42, completeCollection: false, volumesOwned: [1, 2, 3], readingVolume: 8),
            ])
            #expect(try operations().isEmpty)
            await coordinator.stop()
        }

        @Test(.timeLimit(.minutes(1)))
        func `The same update delivered twice is uploaded once`() async throws {
            try seedDragonBall()
            try ReadingListTestSupport.insertManga(
                id: 43,
                title: "Dragon Ball Super",
                volumes: nil,
                updatedAt: Self.t0,
                entry: ReadingListTestSupport.Entry(readingVolume: 1, updatedAt: Self.t0),
                in: container
            )
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, .status(503))
            let (watchSync, coordinator) = makeWatchSync(account: CollectionTestSupport.account)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }

            let update = ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: Self.later)
            // The watch sends every update through two channels, so it normally arrives twice.
            transport.emit(.readingUpdate(update))
            transport.emit(.readingUpdate(update))
            // Events are handled in order: once this one is applied, both copies were handled.
            transport.emit(.readingUpdate(ReadingUpdate(mangaID: 43, readingVolume: 2, sentAt: Self.later)))
            try #require(try await AsyncCondition.waitUntil { try storedEntry(mangaID: 43)?.readingVolume == 2 })
            // Joins the passes the updates asked for and waits until none is left.
            _ = try await coordinator.synchronize()

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [42, 43])
            #expect(try storedEntry(mangaID: 42)?.readingVolume == 8)
            #expect(try operations().isEmpty)
            await coordinator.stop()
        }

        @Test(.timeLimit(.minutes(1)))
        func `An update older than the entry's last change is ignored, queues and uploads nothing, and the list is republished`() async throws {
            try seedDragonBall()
            let (watchSync, coordinator) = makeWatchSync(account: CollectionTestSupport.account)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }

            transport.emit(.readingUpdate(ReadingUpdate(mangaID: 42, readingVolume: 9, sentAt: Self.t0.addingTimeInterval(-60))))
            try #require(await AsyncCondition.waitUntil { !transport.publishedSnapshots.isEmpty })

            #expect(transport.publishedSnapshots.last?.items == [Self.dragonBall(readingVolume: 7, updatedAt: Self.t0)])
            let entry = try #require(try storedEntry(mangaID: 42))
            #expect(entry.readingVolume == 7)
            #expect(entry.updatedAt == Self.t0)
            #expect(try operations().isEmpty)
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)
            await coordinator.stop()
        }

        @Test(.timeLimit(.minutes(1)))
        func `An update for a manga that is not stored is ignored and queues nothing`() async throws {
            try seedDragonBall()
            let (watchSync, _) = makeWatchSync(account: nil)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }

            transport.emit(.readingUpdate(ReadingUpdate(mangaID: 999, readingVolume: 3, sentAt: Self.later)))
            try #require(await AsyncCondition.waitUntil { !transport.publishedSnapshots.isEmpty })

            #expect(transport.publishedSnapshots.last?.items == [Self.dragonBall(readingVolume: 7, updatedAt: Self.t0)])
            #expect(try operations().isEmpty)
            #expect(try PersistenceTestSupport.manga(id: 999, in: PersistenceTestSupport.freshContext(container)) == nil)
        }

        @Test(.timeLimit(.minutes(1)))
        func `An update that arrives while signed out is discarded, queues and uploads nothing, and an empty list is published`() async throws {
            try seedDragonBall()
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            let (watchSync, coordinator) = makeWatchSync(account: nil, isSignedOut: true)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }

            transport.emit(.readingUpdate(ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: Self.later)))
            try #require(await AsyncCondition.waitUntil { !transport.publishedSnapshots.isEmpty })

            #expect(transport.publishedSnapshots.last?.items == [])
            let entry = try #require(try storedEntry(mangaID: 42))
            #expect(entry.readingVolume == 7)
            #expect(entry.updatedAt == Self.t0)
            #expect(try operations().isEmpty)
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)
            await coordinator.stop()
        }

        // MARK: - Other triggers

        @Test(.timeLimit(.minutes(1)))
        func `A pass requested elsewhere publishes the reading list when it finishes`() async throws {
            try seedReadingList()
            let (watchSync, coordinator) = makeWatchSync(account: nil)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }
            // The service follows the passes before it activates the session.
            try #require(await AsyncCondition.waitUntil { transport.activateCalls == 1 })

            await coordinator.requestSync()
            try #require(await AsyncCondition.waitUntil { !transport.publishedSnapshots.isEmpty })

            #expect(transport.publishedSnapshots.last?.items == Self.readingListItems)
        }

        @Test(.timeLimit(.minutes(1)))
        func `While signed out the published list is empty even with mangas being read`() async throws {
            try seedReadingList()
            let (watchSync, _) = makeWatchSync(account: nil, isSignedOut: true)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }

            transport.emit(.activated(isReachable: true))
            try #require(await AsyncCondition.waitUntil { !transport.publishedSnapshots.isEmpty })

            #expect(transport.publishedSnapshots.last?.items == [])
        }

        @Test(.timeLimit(.minutes(1)))
        func `A failed publish does not stop the service: once the watch accepts again, the next event publishes`() async throws {
            try seedDragonBall()
            transport.configure { $0.contextError = .payloadTooLarge }
            let (watchSync, _) = makeWatchSync(account: nil)
            let running = Task { await watchSync.start() }
            defer {
                running.cancel()
                transport.finish()
            }

            transport.emit(.activated(isReachable: true))
            // Handled after the publish of the activation failed.
            transport.emit(.readingUpdate(ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: Self.later)))
            try #require(try await AsyncCondition.waitUntil { try storedEntry(mangaID: 42)?.readingVolume == 8 })
            transport.configure { $0.contextError = nil }
            transport.emit(.reachabilityChanged(isReachable: true))

            let expected = [Self.dragonBall(readingVolume: 8, updatedAt: Self.later)]
            try #require(await AsyncCondition.waitUntil { transport.publishedSnapshots.last?.items == expected })
        }
    }
}
