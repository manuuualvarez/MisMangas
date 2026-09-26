//
//  MangaSyncActorSyncTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// The store side of a synchronization pass: the server snapshot applied in one transaction
/// around the queued operations, the outbox counters and clearing, and the drain discarding rows
/// it can never send. Every test owns an in-memory container, so the suite runs in parallel.
/// Oracles: the literal values of `collection_response.json`, the fixed dates each call
/// receives, the fields the test itself saved, and what a fresh `ModelContext` reads afterwards.
@Suite("MangaSyncActor synchronization")
struct MangaSyncActorSyncTests {
    // Fixed clock: every date is an explicit instant, never the wall clock.
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let t1 = Date(timeIntervalSinceReferenceDate: 800_000_100)
    private static let t2 = Date(timeIntervalSinceReferenceDate: 800_000_200)
    private static let t3 = Date(timeIntervalSinceReferenceDate: 800_000_300)

    // MARK: - applyRemoteSnapshot

    @Test func `A snapshot on an empty store stores every entry with its nested manga and queues nothing`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()

        let result = try await actor.applyRemoteSnapshot(CollectionTestSupport.remoteCollection(), now: Self.t1)

        #expect(result.upserted == 2)
        #expect(result.removed == 0)
        let context = PersistenceTestSupport.freshContext(container)
        let entries = try CollectionTestSupport.entries(in: context)
        #expect(entries.map(\.mangaID) == [1, 2])
        #expect(entries.first?.volumesOwned == Array(1 ... 18))
        #expect(entries.first?.readingVolume == 12)
        #expect(entries.first?.completeCollection == true)
        #expect(entries.last?.volumesOwned == [1, 2, 3])
        #expect(entries.last?.readingVolume == nil)
        #expect(entries.last?.completeCollection == false)
        let mangas = try PersistenceTestSupport.mangasByID(in: context)
        #expect(mangas.map(\.title) == ["Monster", "Berserk"])
        #expect(mangas.allSatisfy { $0.inCollection })
        #expect(try CollectionTestSupport.operations(in: context).isEmpty)
    }

    @Test func `A snapshot leaves the entries of mangas with a pending or blocked operation as the user saved them`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
        try await actor.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: nil, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: 2, volumesOwned: [2], readingVolume: nil, completeCollection: false, account: nil, now: Self.t1)
        try await CollectionTestSupport.block(mangaID: 2, in: actor, container: container, now: Self.t1)
        // The server has Monster and Berserk with other values, plus a third entry nobody queued.
        let remote = try CollectionTestSupport.remoteCollection()
        let third = try #require(remote.last).replacing(mangaID: 3)

        let result = try await actor.applyRemoteSnapshot(remote + [third], now: Self.t2)

        #expect(result.upserted == 1)
        #expect(result.removed == 0)
        let context = PersistenceTestSupport.freshContext(container)
        let entries = try CollectionTestSupport.entries(in: context)
        #expect(entries.map(\.mangaID) == [1, 2, 3])
        #expect(entries.map(\.volumesOwned) == [[1], [2], [1, 2, 3]])
        #expect(entries.first?.updatedAt == Self.t1)
        #expect(try CollectionTestSupport.operations(in: context).map(\.mangaID) == [1, 2])
    }

    @Test func `A snapshot removes the local entries the server no longer has, except pending or blocked ones, and queues nothing`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let remote = try CollectionTestSupport.remoteCollection()
        let berserk = try #require(remote.last)
        // 50: the server's truth from an earlier pass, nothing queued.
        try await actor.upsertCollectionEntry(from: berserk.replacing(mangaID: 50), now: Self.t0)
        // 51: pending; 52: blocked.
        try await CollectionTestSupport.storeMangas([51, 52], in: actor, now: Self.t0)
        try await actor.saveCollectionEntry(mangaID: 51, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: nil, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: 52, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: nil, now: Self.t1)
        try await CollectionTestSupport.block(mangaID: 52, in: actor, container: container, now: Self.t1)

        let result = try await actor.applyRemoteSnapshot([], now: Self.t2)

        #expect(result.upserted == 0)
        #expect(result.removed == 1)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.entries(in: context).map(\.mangaID) == [51, 52])
        let removedManga = try #require(try PersistenceTestSupport.manga(id: 50, in: context))
        #expect(!removedManga.inCollection)
        #expect(try CollectionTestSupport.operations(in: context).map(\.mangaID) == [51, 52])
    }

    @Test func `A snapshot that repeats the stored entries keeps their updatedAt and refreshes the cached manga`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let remote = try CollectionTestSupport.remoteCollection()
        _ = try await actor.applyRemoteSnapshot(remote, now: Self.t1)
        let seeded = try CollectionTestSupport.entries(in: PersistenceTestSupport.freshContext(container))
        try #require(seeded.map(\.updatedAt) == [Self.t1, Self.t1])

        _ = try await actor.applyRemoteSnapshot(remote, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.entries(in: context).map(\.updatedAt) == [Self.t1, Self.t1])
        #expect(try PersistenceTestSupport.mangasByID(in: context).map(\.cachedAt) == [Self.t2, Self.t2])
    }

    @Test func `A snapshot that changes the user fields of an entry stamps it with the new date`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let remote = try CollectionTestSupport.remoteCollection()
        _ = try await actor.applyRemoteSnapshot(remote, now: Self.t1)
        let berserk = try #require(remote.last)

        _ = try await actor.applyRemoteSnapshot([#require(remote.first), berserk.replacing(volumesOwned: [1, 2, 3, 4])], now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let entries = try CollectionTestSupport.entries(in: context)
        #expect(entries.map(\.updatedAt) == [Self.t1, Self.t2])
        #expect(entries.last?.volumesOwned == [1, 2, 3, 4])
    }

    // MARK: - Outbox

    @Test func `pendingOperationCounts tells the operations in the drain from the blocked ones`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2, 3], in: actor, now: Self.t0)
        for id in [1, 2, 3] {
            try await actor.saveCollectionEntry(mangaID: id, volumesOwned: [id], readingVolume: nil, completeCollection: false, account: nil, now: Self.t1)
        }
        try await CollectionTestSupport.block(mangaID: 2, in: actor, container: container, now: Self.t2)

        let counts = try await actor.pendingOperationCounts(for: CollectionTestSupport.account)

        #expect(counts.pending == 2)
        #expect(counts.blocked == 1)
    }

    @Test func `clearOutbox deletes every queued operation and keeps the entries`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
        try await actor.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: nil, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: 2, volumesOwned: [2], readingVolume: nil, completeCollection: true, account: nil, now: Self.t2)
        try await CollectionTestSupport.block(mangaID: 2, in: actor, container: container, now: Self.t3)

        try await actor.clearOutbox()

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.operations(in: context).isEmpty)
        let entries = try CollectionTestSupport.entries(in: context)
        #expect(entries.map(\.mangaID) == [1, 2])
        #expect(entries.map(\.volumesOwned) == [[1], [2]])
    }

    @Test func `The drain deletes a queued row whose operation type it cannot read and returns the valid ones`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let seeding = PersistenceTestSupport.freshContext(container)
        let unreadable = PendingOperation(operationType: .upsert, mangaID: 77, createdAt: Self.t0)
        unreadable.operationType = "rename"
        seeding.insert(unreadable)
        try seeding.save()
        try await CollectionTestSupport.storeMangas([1], in: actor, now: Self.t0)
        try await actor.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: nil, now: Self.t1)

        let drained = try await actor.drainPendingOperations(for: CollectionTestSupport.account)

        #expect(drained.map(\.mangaID) == [1])
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.operations(in: context).map(\.mangaID) == [1])
    }

    // MARK: - Owner of each queued operation

    private static let accountA = "a@example.com"
    private static let accountB = "b@example.com"

    /// Queues an upsert of `mangaID` made under `account` (`nil`: a guest) at `now`.
    private static func queueSave(_ mangaID: Int, account: String?, now: Date, in actor: MangaSyncActor) async throws {
        try await actor.saveCollectionEntry(
            mangaID: mangaID,
            volumesOwned: [1],
            readingVolume: nil,
            completeCollection: false,
            account: account,
            now: now
        )
    }

    @Test func `A save and a removal stamp on their queued operation the account they were made under`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)

        try await Self.queueSave(1, account: Self.accountA, now: Self.t1, in: actor)
        try await Self.queueSave(2, account: nil, now: Self.t1, in: actor)
        try await actor.removeCollectionEntry(mangaID: 3, account: Self.accountA, now: Self.t1)
        try await actor.removeCollectionEntry(mangaID: 4, account: nil, now: Self.t1)

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try CollectionTestSupport.operationsByManga(in: context)
        #expect(operations.map(\.mangaID) == [1, 2, 3, 4])
        #expect(operations.map(\.operationType) == ["upsert", "upsert", "delete", "delete"])
        #expect(operations.map(\.account) == [Self.accountA, nil, Self.accountA, nil])
    }

    @Test func `A new intention for a manga replaces its queued operation together with the account that owned it`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
        try await Self.queueSave(1, account: Self.accountA, now: Self.t1, in: actor)
        try await Self.queueSave(2, account: nil, now: Self.t1, in: actor)

        try await Self.queueSave(1, account: nil, now: Self.t2, in: actor)
        try await actor.removeCollectionEntry(mangaID: 2, account: Self.accountB, now: Self.t2)

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try CollectionTestSupport.operationsByManga(in: context)
        #expect(operations.map(\.mangaID) == [1, 2])
        #expect(operations.map(\.account) == [nil, Self.accountB])
    }

    @Test func `Draining for an account returns its operations and the guest's oldest first, deletes another account's and adopts the guest's`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2, 3], in: actor, now: Self.t0)
        // Oldest first: a guest delete (4), another account's save (1), a guest save (2), then one of B (3).
        try await actor.removeCollectionEntry(mangaID: 4, account: nil, now: Self.t0)
        try await Self.queueSave(1, account: Self.accountA, now: Self.t1, in: actor)
        try await Self.queueSave(2, account: nil, now: Self.t2, in: actor)
        try await Self.queueSave(3, account: Self.accountB, now: Self.t3, in: actor)

        let drained = try await actor.drainPendingOperations(for: Self.accountB)

        #expect(drained.map(\.mangaID) == [4, 2, 3])
        #expect(drained.map(\.type) == [.delete, .upsert, .upsert])
        let context = PersistenceTestSupport.freshContext(container)
        let remaining = try CollectionTestSupport.operations(in: context)
        #expect(remaining.map(\.mangaID) == [4, 2, 3])
        #expect(remaining.map(\.account) == [Self.accountB, Self.accountB, Self.accountB])
        // The entry A saved stays on the device; only its upload is gone.
        #expect(try CollectionTestSupport.entries(in: context).map(\.mangaID) == [1, 2, 3])
    }

    @Test func `Draining for an account deletes another account's blocked operations and adopts the guest's blocked ones without returning them`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2, 3], in: actor, now: Self.t0)
        try await Self.queueSave(1, account: Self.accountA, now: Self.t1, in: actor)
        try await Self.queueSave(2, account: nil, now: Self.t1, in: actor)
        try await Self.queueSave(3, account: Self.accountB, now: Self.t1, in: actor)
        try await CollectionTestSupport.block(mangaID: 1, in: actor, container: container, now: Self.t2)
        try await CollectionTestSupport.block(mangaID: 2, in: actor, container: container, now: Self.t2)

        let drained = try await actor.drainPendingOperations(for: Self.accountB)

        #expect(drained.map(\.mangaID) == [3])
        let context = PersistenceTestSupport.freshContext(container)
        let remaining = try CollectionTestSupport.operationsByManga(in: context)
        #expect(remaining.map(\.mangaID) == [2, 3])
        #expect(remaining.map(\.account) == [Self.accountB, Self.accountB])
        #expect(remaining.first?.blockedAt == Self.t2)
    }

    @Test(arguments: [
        (CollectionTestSupport.otherAccount as String?, 3, 1),
        (MangaSyncActorSyncTests.accountA as String?, 3, 2),
        (nil as String?, 2, 1),
    ])
    func `pendingOperationCounts counts the operations of the account and the guest's, and changes nothing`(account: String?, pending: Int, blocked: Int) async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas(Array(1 ... 6), in: actor, now: Self.t0)
        // A: 1 pending, 2 blocked. Guest: 3 and 4 pending, 5 blocked. Other account: 6 pending.
        try await Self.queueSave(1, account: Self.accountA, now: Self.t1, in: actor)
        try await Self.queueSave(2, account: Self.accountA, now: Self.t1, in: actor)
        try await Self.queueSave(3, account: nil, now: Self.t1, in: actor)
        try await Self.queueSave(4, account: nil, now: Self.t1, in: actor)
        try await Self.queueSave(5, account: nil, now: Self.t1, in: actor)
        try await Self.queueSave(6, account: CollectionTestSupport.otherAccount, now: Self.t1, in: actor)
        try await CollectionTestSupport.block(mangaID: 2, in: actor, container: container, now: Self.t2)
        try await CollectionTestSupport.block(mangaID: 5, in: actor, container: container, now: Self.t2)

        let counts = try await actor.pendingOperationCounts(for: account)

        #expect(counts.pending == pending)
        #expect(counts.blocked == blocked)
        let context = PersistenceTestSupport.freshContext(container)
        let stored = try CollectionTestSupport.operationsByManga(in: context)
        #expect(stored.map(\.account) == [Self.accountA, Self.accountA, nil, nil, nil, CollectionTestSupport.otherAccount])
    }

    // MARK: - Handing the collection over to another account

    @Test func `handOverCollection keeps only the changes of the new account and the guest's, and the entries they touch`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2, 3, 4], in: actor, now: Self.t0)
        // Manga 1: synced by the previous account, nothing queued.
        try await actor.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: Self.accountA, now: Self.t0)
        try await actor.clearOutbox()
        try await actor.saveCollectionEntry(mangaID: 2, volumesOwned: [2], readingVolume: nil, completeCollection: false, account: nil, now: Self.t0)
        try await actor.saveCollectionEntry(mangaID: 3, volumesOwned: [3], readingVolume: nil, completeCollection: false, account: Self.accountA, now: Self.t0)
        try await actor.saveCollectionEntry(mangaID: 4, volumesOwned: [4], readingVolume: nil, completeCollection: false, account: Self.accountB, now: Self.t0)

        try await actor.handOverCollection(to: Self.accountB)

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.entries(in: context).map(\.mangaID) == [2, 4])
        let operations = try CollectionTestSupport.operationsByManga(in: context)
        #expect(operations.map(\.mangaID) == [2, 4])
        #expect(operations.map(\.account) == [nil, Self.accountB])
        let mangas = try context.fetch(FetchDescriptor<Manga>(sortBy: [SortDescriptor(\.id)]))
        #expect(mangas.map(\.inCollection) == [false, true, false, true])
    }
}
