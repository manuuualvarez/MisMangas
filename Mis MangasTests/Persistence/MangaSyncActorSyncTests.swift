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
        try await actor.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: 2, volumesOwned: [2], readingVolume: nil, completeCollection: false, now: Self.t1)
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
        try await actor.saveCollectionEntry(mangaID: 51, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: 52, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
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
            try await actor.saveCollectionEntry(mangaID: id, volumesOwned: [id], readingVolume: nil, completeCollection: false, now: Self.t1)
        }
        try await CollectionTestSupport.block(mangaID: 2, in: actor, container: container, now: Self.t2)

        let counts = try await actor.pendingOperationCounts()

        #expect(counts.pending == 2)
        #expect(counts.blocked == 1)
    }

    @Test func `clearOutbox deletes every queued operation and keeps the entries`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
        try await actor.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)
        try await actor.saveCollectionEntry(mangaID: 2, volumesOwned: [2], readingVolume: nil, completeCollection: true, now: Self.t2)
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
        try await actor.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, now: Self.t1)

        let drained = try await actor.drainPendingOperations()

        #expect(drained.map(\.mangaID) == [1])
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.operations(in: context).map(\.mangaID) == [1])
    }
}
