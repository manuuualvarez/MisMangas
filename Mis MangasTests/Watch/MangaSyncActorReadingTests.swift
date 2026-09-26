//
//  MangaSyncActorReadingTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// The iPhone side of the watch reading list on `MangaSyncActor`: which mangas count as being
/// read, the list published to the watch, and how a volume chosen on the watch reaches the store
/// and the outbox. The store is seeded through a fresh context with dates chosen here; the oracle
/// is what another fresh context reads afterwards and the values written by hand below.
@Suite("MangaSyncActor reading list")
struct MangaSyncActorReadingTests {
    private typealias Entry = ReadingListTestSupport.Entry

    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let dragonBallCover = "https://cdn.myanimelist.net/images/manga/1/267793l.jpg"

    private let actor: MangaSyncActor
    private let container: ModelContainer

    init() throws {
        let made = try PersistenceTestSupport.makeActor()
        actor = made.actor
        container = made.container
    }

    // MARK: - Being read

    struct ReadingCase: CustomTestStringConvertible {
        let name: String
        let volumes: Int?
        let entry: ReadingListTestSupport.Entry?
        let isReading: Bool

        var testDescription: String {
            name
        }
    }

    static let readingCases = [
        ReadingCase(name: "not in the collection", volumes: 10, entry: nil, isReading: false),
        ReadingCase(
            name: "no reading volume",
            volumes: 10,
            entry: Entry(readingVolume: nil, volumesOwned: [1, 2], updatedAt: t0),
            isReading: false
        ),
        ReadingCase(
            name: "collection marked complete",
            volumes: 10,
            entry: Entry(readingVolume: 5, completeCollection: true, updatedAt: t0),
            isReading: false
        ),
        ReadingCase(name: "on the last volume", volumes: 10, entry: Entry(readingVolume: 10, updatedAt: t0), isReading: true),
        ReadingCase(name: "volume count unknown", volumes: nil, entry: Entry(readingVolume: 3, updatedAt: t0), isReading: true),
        ReadingCase(name: "before the last volume", volumes: 10, entry: Entry(readingVolume: 3, updatedAt: t0), isReading: true),
    ]

    @Test(arguments: readingCases)
    func `A manga is being read only with a reading volume and a collection not marked complete`(_ readingCase: ReadingCase) throws {
        try ReadingListTestSupport.insertManga(
            id: 1,
            volumes: readingCase.volumes,
            updatedAt: Self.t0,
            entry: readingCase.entry,
            in: container
        )

        let manga = try #require(try PersistenceTestSupport.manga(id: 1, in: PersistenceTestSupport.freshContext(container)))
        #expect(manga.isReading == readingCase.isReading)
    }

    // MARK: - Snapshot

    /// Three mangas being read whose entries changed in the opposite order to their records (the
    /// catalog stamps `Manga.updatedAt` too), and three that are not being read.
    private func seedMixedCollection() throws {
        try ReadingListTestSupport.insertManga(
            id: 1,
            title: "Monster",
            volumes: 18,
            coverURL: "https://cdn.myanimelist.net/images/manga/3/258224l.jpg",
            updatedAt: Self.t0.addingTimeInterval(300),
            entry: Entry(readingVolume: 3, volumesOwned: [1, 2, 3], updatedAt: Self.t0.addingTimeInterval(10)),
            in: container
        )
        try ReadingListTestSupport.insertManga(
            id: 2,
            title: "Berserk",
            volumes: nil,
            coverURL: "https://cdn.myanimelist.net/images/manga/1/157897l.jpg",
            updatedAt: Self.t0.addingTimeInterval(100),
            entry: Entry(readingVolume: 5, updatedAt: Self.t0.addingTimeInterval(30)),
            in: container
        )
        try ReadingListTestSupport.insertManga(
            id: 42,
            title: "Dragon Ball",
            volumes: 42,
            coverURL: nil,
            updatedAt: Self.t0.addingTimeInterval(200),
            entry: Entry(readingVolume: 42, updatedAt: Self.t0.addingTimeInterval(20)),
            in: container
        )
        try ReadingListTestSupport.insertManga(
            id: 4,
            volumes: 7,
            updatedAt: Self.t0.addingTimeInterval(500),
            entry: Entry(readingVolume: 7, completeCollection: true, updatedAt: Self.t0.addingTimeInterval(40)),
            in: container
        )
        try ReadingListTestSupport.insertManga(
            id: 5,
            volumes: 12,
            updatedAt: Self.t0.addingTimeInterval(600),
            entry: Entry(readingVolume: nil, volumesOwned: [1], updatedAt: Self.t0.addingTimeInterval(50)),
            in: container
        )
        try ReadingListTestSupport.insertManga(id: 6, volumes: 30, updatedAt: Self.t0.addingTimeInterval(700), entry: nil, in: container)
    }

    /// The mangas being read of `seedMixedCollection()`, most recently changed entry first.
    private static let expectedItems = [
        ReadingItem(
            mangaID: 2,
            title: "Berserk",
            coverURL: "https://cdn.myanimelist.net/images/manga/1/157897l.jpg",
            readingVolume: 5,
            volumes: nil,
            completeCollection: false,
            updatedAt: t0.addingTimeInterval(30)
        ),
        ReadingItem(
            mangaID: 42,
            title: "Dragon Ball",
            coverURL: nil,
            readingVolume: 42,
            volumes: 42,
            completeCollection: false,
            updatedAt: t0.addingTimeInterval(20)
        ),
        ReadingItem(
            mangaID: 1,
            title: "Monster",
            coverURL: "https://cdn.myanimelist.net/images/manga/3/258224l.jpg",
            readingVolume: 3,
            volumes: 18,
            completeCollection: false,
            updatedAt: t0.addingTimeInterval(10)
        ),
    ]

    @Test func `The reading snapshot holds only the mangas being read, most recently changed entry first, dated by the entry`() async throws {
        try seedMixedCollection()
        let now = Self.t0.addingTimeInterval(1000)

        let snapshot = try await actor.readingSnapshot(limit: 50, now: now)

        #expect(snapshot == ReadingSnapshot(generatedAt: now, items: Self.expectedItems))
    }

    @Test func `The reading snapshot keeps the most recently changed entries up to the limit`() async throws {
        try seedMixedCollection()
        let now = Self.t0.addingTimeInterval(1000)

        let snapshot = try await actor.readingSnapshot(limit: 2, now: now)

        #expect(snapshot == ReadingSnapshot(generatedAt: now, items: Array(Self.expectedItems.prefix(2))))
    }

    // MARK: - Update from the watch

    /// Dragon Ball in the collection, reading volume 7 of 42, entry last changed at `t0` and the
    /// record at another moment, so a stamp on the wrong model shows.
    private func seedDragonBall() throws {
        try ReadingListTestSupport.insertManga(
            id: 42,
            title: "Dragon Ball",
            volumes: 42,
            coverURL: Self.dragonBallCover,
            updatedAt: Self.t0.addingTimeInterval(-100),
            entry: Entry(readingVolume: 7, volumesOwned: [1, 2, 3], updatedAt: Self.t0),
            in: container
        )
    }

    /// A moment after the entry's last change, with a fraction so a rounded date would show.
    private static let sentAt = t0.addingTimeInterval(60.125)
    /// When the iPhone receives the update: dates the queued operation, never the entry.
    private static let receivedAt = t0.addingTimeInterval(500)

    private func freshContext() -> ModelContext {
        PersistenceTestSupport.freshContext(container)
    }

    @Test(arguments: [CollectionTestSupport.account, nil] as [String?])
    func `A later update applies the volume, stamps entry and manga with sentAt and queues one upsert under the given account`(account: String?) async throws {
        try seedDragonBall()

        let isApplied = try await actor.applyReadingUpdate(
            mangaID: 42,
            readingVolume: 8,
            sentAt: Self.sentAt,
            account: account,
            now: Self.receivedAt
        )

        #expect(isApplied)
        let context = freshContext()
        let entry = try #require(try CollectionTestSupport.entry(mangaID: 42, in: context))
        #expect(entry.readingVolume == 8)
        #expect(entry.volumesOwned == [1, 2, 3])
        #expect(entry.completeCollection == false)
        #expect(entry.updatedAt == Self.sentAt)
        let manga = try #require(try PersistenceTestSupport.manga(id: 42, in: context))
        #expect(manga.updatedAt == Self.sentAt)
        #expect(manga.inCollection)
        let operations = try CollectionTestSupport.operations(in: context)
        try #require(operations.count == 1)
        let operation = operations[0]
        #expect(operation.operationType == PendingOperationType.upsert.rawValue)
        #expect(operation.mangaID == 42)
        #expect(operation.account == account)
        #expect(operation.createdAt == Self.receivedAt)
        #expect(try ReadingListTestSupport.request(of: operation) == UserMangaCollectionRequest(
            manga: 42,
            completeCollection: false,
            volumesOwned: [1, 2, 3],
            readingVolume: 8
        ))
    }

    @Test func `The second copy of an update returns false and leaves the single operation of the first`() async throws {
        try seedDragonBall()
        let account = CollectionTestSupport.account

        let first = try await actor.applyReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: Self.sentAt, account: account, now: Self.receivedAt)
        let second = try await actor.applyReadingUpdate(
            mangaID: 42,
            readingVolume: 8,
            sentAt: Self.sentAt,
            account: account,
            now: Self.receivedAt.addingTimeInterval(5)
        )

        #expect(first)
        #expect(second == false)
        let context = freshContext()
        let operations = try CollectionTestSupport.operations(in: context)
        try #require(operations.count == 1)
        #expect(operations[0].createdAt == Self.receivedAt)
        #expect(try ReadingListTestSupport.request(of: operations[0]).readingVolume == 8)
        #expect(try CollectionTestSupport.entry(mangaID: 42, in: context)?.updatedAt == Self.sentAt)
    }

    /// Offsets from the date of the change already applied: an update sent at the same moment and
    /// one sent before it (it arrived late through the other channel).
    @Test(arguments: [0, -30] as [TimeInterval])
    func `An update not later than the entry's last change returns false and changes nothing`(offset: TimeInterval) async throws {
        try seedDragonBall()
        let account = CollectionTestSupport.account
        let applied = try await actor.applyReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: Self.sentAt, account: account, now: Self.receivedAt)

        let isApplied = try await actor.applyReadingUpdate(
            mangaID: 42,
            readingVolume: 3,
            sentAt: Self.sentAt.addingTimeInterval(offset),
            account: CollectionTestSupport.otherAccount,
            now: Self.receivedAt.addingTimeInterval(5)
        )

        #expect(applied)
        #expect(isApplied == false)
        let context = freshContext()
        let entry = try #require(try CollectionTestSupport.entry(mangaID: 42, in: context))
        #expect(entry.readingVolume == 8)
        #expect(entry.updatedAt == Self.sentAt)
        #expect(try PersistenceTestSupport.manga(id: 42, in: context)?.updatedAt == Self.sentAt)
        let operations = try CollectionTestSupport.operations(in: context)
        try #require(operations.count == 1)
        #expect(operations[0].account == account)
        #expect(operations[0].createdAt == Self.receivedAt)
        #expect(try ReadingListTestSupport.request(of: operations[0]).readingVolume == 8)
    }

    @Test func `An update for a manga outside the collection or not stored returns false and queues nothing for it`() async throws {
        try seedDragonBall()
        try ReadingListTestSupport.insertManga(id: 7, volumes: 20, updatedAt: Self.t0, entry: nil, in: container)
        let account = CollectionTestSupport.account

        let withoutEntry = try await actor.applyReadingUpdate(mangaID: 7, readingVolume: 2, sentAt: Self.sentAt, account: account, now: Self.receivedAt)
        let notStored = try await actor.applyReadingUpdate(mangaID: 999, readingVolume: 2, sentAt: Self.sentAt, account: account, now: Self.receivedAt)
        // A manga in the collection, so the outcome above is the rule and not a method that does nothing.
        let inCollection = try await actor.applyReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: Self.sentAt, account: account, now: Self.receivedAt)

        #expect(withoutEntry == false)
        #expect(notStored == false)
        #expect(inCollection)
        let context = freshContext()
        #expect(try CollectionTestSupport.operations(in: context).map(\.mangaID) == [42])
        #expect(try CollectionTestSupport.entry(mangaID: 7, in: context) == nil)
        let manga = try #require(try PersistenceTestSupport.manga(id: 7, in: context))
        #expect(manga.inCollection == false)
        #expect(manga.updatedAt == Self.t0)
        #expect(try PersistenceTestSupport.manga(id: 999, in: context) == nil)
    }

    @Test func `A reading volume above the volume limit is stored and uploaded at the limit`() async throws {
        try seedDragonBall()

        let isApplied = try await actor.applyReadingUpdate(
            mangaID: 42,
            readingVolume: UserCollectionEntry.volumeLimit + 200,
            sentAt: Self.sentAt,
            account: CollectionTestSupport.account,
            now: Self.receivedAt
        )

        #expect(isApplied)
        let context = freshContext()
        #expect(try CollectionTestSupport.entry(mangaID: 42, in: context)?.readingVolume == UserCollectionEntry.volumeLimit)
        let operation = try #require(try CollectionTestSupport.operations(in: context).first)
        #expect(try ReadingListTestSupport.request(of: operation).readingVolume == UserCollectionEntry.volumeLimit)
    }

    struct PreviousOperation: CustomTestStringConvertible {
        let type: PendingOperationType
        let account: String?

        var testDescription: String {
            "\(type.rawValue) by \(account ?? "a guest")"
        }
    }

    @Test(arguments: [
        PreviousOperation(type: .delete, account: CollectionTestSupport.otherAccount),
        PreviousOperation(type: .upsert, account: nil),
    ])
    func `An applied update replaces the queued operation of that manga with its own upsert`(previous: PreviousOperation) async throws {
        try seedDragonBall()
        try ReadingListTestSupport.queueOperation(
            previous.type,
            mangaID: 42,
            account: previous.account,
            createdAt: Self.t0.addingTimeInterval(-5),
            in: container
        )

        let isApplied = try await actor.applyReadingUpdate(
            mangaID: 42,
            readingVolume: 8,
            sentAt: Self.sentAt,
            account: CollectionTestSupport.account,
            now: Self.receivedAt
        )

        #expect(isApplied)
        let operations = try CollectionTestSupport.operations(in: freshContext())
        try #require(operations.count == 1)
        let operation = operations[0]
        #expect(operation.operationType == PendingOperationType.upsert.rawValue)
        #expect(operation.account == CollectionTestSupport.account)
        #expect(operation.createdAt == Self.receivedAt)
        #expect(try ReadingListTestSupport.request(of: operation).readingVolume == 8)
    }
}
