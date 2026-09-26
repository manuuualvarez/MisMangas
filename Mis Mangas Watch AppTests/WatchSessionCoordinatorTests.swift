//
//  WatchSessionCoordinatorTests.swift
//  Mis Mangas Watch AppTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas_Watch_App
import SwiftData
import Testing

/// The watch end of the connection: activation, reading lists arriving from the iPhone through a
/// `FakeWatchTransport`, and the background task that waits for pending content.
///
/// Oracles, never the code under test: the fake's call counts, what a fresh `ModelContext` reads
/// from the in-memory store, the date read straight from an isolated `UserDefaults` suite, and the
/// wall-clock interval the test measures around the arrival. The coordinator applies what arrives
/// on its own task, so every effect is awaited with a bounded poll.
///
/// A class only for `deinit`, which ends the fake's event stream and removes the suite.
@Suite("WatchSessionCoordinator", .timeLimit(.minutes(1)))
final class WatchSessionCoordinatorTests {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let t1 = Date(timeIntervalSinceReferenceDate: 800_000_100.5)
    private static let t2 = Date(timeIntervalSinceReferenceDate: 800_000_200.25)

    private static let dragonBall = ReadingItem(
        mangaID: 42,
        title: "Dragon Ball",
        coverURL: "https://cdn.myanimelist.net/images/manga/1/267793l.jpg",
        readingVolume: 7,
        volumes: 42,
        completeCollection: false,
        updatedAt: t1
    )
    private static let berserk = ReadingItem(
        mangaID: 2,
        title: "Berserk",
        coverURL: nil,
        readingVolume: 3,
        volumes: nil,
        completeCollection: false,
        updatedAt: t2
    )

    /// How long a call that must still be waiting is given to return early.
    private static let stillWaiting: Duration = .milliseconds(300)

    private let transport: FakeWatchTransport
    private let container: ModelContainer
    private let defaults: UserDefaults
    private let suiteName: String
    private let coordinator: WatchSessionCoordinator

    init() throws {
        let suiteName = "WatchSessionCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let made = try WatchPersistenceTestSupport.makeActor()
        let transport = FakeWatchTransport()
        self.suiteName = suiteName
        self.defaults = defaults
        self.transport = transport
        container = made.container
        coordinator = WatchSessionCoordinator(transport: transport, syncActor: made.actor, defaultsSuiteName: suiteName)
    }

    deinit {
        transport.finish()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// The arrival date the coordinator stored, read without going through it.
    private var storedSnapshotDate: Date? {
        defaults.object(forKey: WatchSessionCoordinator.lastSnapshotKey) as? Date
    }

    // MARK: - Activation

    @Test func `Starting activates the session once, however many times it is called`() async {
        await coordinator.start()
        await coordinator.start()

        #expect(await WatchPersistenceTestSupport.waitUntil { self.transport.activateCalls >= 1 })
        #expect(transport.activateCalls == 1)
    }

    // MARK: - Snapshots

    @Test func `A reading list from the iPhone fills the store and records when it arrived`() async throws {
        await coordinator.start()
        let beforeArrival = Date.now

        transport.emit(.readingSnapshot(ReadingSnapshot(generatedAt: Self.t0, items: [Self.berserk, Self.dragonBall])))

        let isApplied = try await WatchPersistenceTestSupport.waitUntil {
            try WatchPersistenceTestSupport.mangaIDs(in: self.container) == [2, 42] && self.storedSnapshotDate != nil
        }
        try #require(isApplied)
        let afterArrival = Date.now

        let context = WatchPersistenceTestSupport.freshContext(container)
        let manga = try #require(try WatchPersistenceTestSupport.manga(id: 42, in: context))
        #expect(manga.title == "Dragon Ball")
        #expect(manga.collectionEntry?.readingVolume == 7)
        #expect(manga.collectionEntry?.updatedAt == Self.t1)
        #expect(try WatchPersistenceTestSupport.entryMangaIDs(in: container) == [2, 42])

        // The date of arrival on the watch, not the date the iPhone generated the list.
        let stored = try #require(storedSnapshotDate)
        #expect(stored >= beforeArrival && stored <= afterArrival)
        #expect(await coordinator.lastSnapshotAt == stored)
    }

    @Test func `A later reading list without a manga deletes it from the store`() async throws {
        await coordinator.start()
        transport.emit(.readingSnapshot(ReadingSnapshot(generatedAt: Self.t0, items: [Self.berserk, Self.dragonBall])))
        let isFirstApplied = try await WatchPersistenceTestSupport.waitUntil {
            try WatchPersistenceTestSupport.mangaIDs(in: self.container) == [2, 42]
        }
        try #require(isFirstApplied)

        transport.emit(.readingSnapshot(ReadingSnapshot(generatedAt: Self.t2, items: [Self.dragonBall])))

        let isSecondApplied = try await WatchPersistenceTestSupport.waitUntil {
            try WatchPersistenceTestSupport.mangaIDs(in: self.container) == [42]
        }
        #expect(isSecondApplied)
        #expect(try WatchPersistenceTestSupport.entryMangaIDs(in: container) == [42])
    }

    // MARK: - Background content

    @Test func `Receiving pending content activates, waits while content is pending and returns with the list applied`() async throws {
        transport.configure { $0.hasContentPending = true }
        let completion = Completion()
        let coordinator = self.coordinator
        let task = Task {
            await coordinator.receivePendingContent()
            await completion.markDone()
        }
        transport.emit(.activated(isReachable: true))

        let hasReturnedEarly = await WatchPersistenceTestSupport.waitUntil(timeout: Self.stillWaiting) { await completion.isDone }
        #expect(!hasReturnedEarly)
        #expect(transport.activateCalls == 1)

        // As the session does: the content is delivered first, then no longer reported pending.
        transport.emit(.readingSnapshot(ReadingSnapshot(generatedAt: Self.t0, items: [Self.dragonBall])))
        transport.configure { $0.hasContentPending = false }

        let hasReturned = await WatchPersistenceTestSupport.waitUntil { await completion.isDone }
        #expect(hasReturned)
        #expect(try WatchPersistenceTestSupport.mangaIDs(in: container) == [42])
        task.cancel()
    }

    @Test func `Receiving pending content returns once its task is cancelled while content is still pending`() async {
        transport.configure { $0.hasContentPending = true }
        let completion = Completion()
        let coordinator = self.coordinator
        let task = Task {
            await coordinator.receivePendingContent()
            await completion.markDone()
        }
        transport.emit(.activated(isReachable: true))

        let hasReturnedEarly = await WatchPersistenceTestSupport.waitUntil(timeout: Self.stillWaiting) { await completion.isDone }
        #expect(!hasReturnedEarly)

        task.cancel()

        #expect(await WatchPersistenceTestSupport.waitUntil { await completion.isDone })
    }
}

/// Records that a call made on another task has returned.
private actor Completion {
    private(set) var isDone = false

    func markDone() {
        isDone = true
    }
}
