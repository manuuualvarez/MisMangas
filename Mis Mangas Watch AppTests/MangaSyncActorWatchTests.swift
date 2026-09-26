//
//  MangaSyncActorWatchTests.swift
//  Mis Mangas Watch AppTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas_Watch_App
import SwiftData
import Testing

/// The watch side of `MangaSyncActor`: the reading list published by the iPhone replaces the
/// watch's store, and a volume chosen on the watch is written locally without queueing anything
/// (the watch has no server). The store is seeded through a fresh context with dates chosen here;
/// the oracle is what another fresh context reads afterwards and the values written by hand below.
@Suite("MangaSyncActor on the watch")
struct MangaSyncActorWatchTests {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Fractions of a second, so a date truncated anywhere on the way no longer matches.
    private static let t1 = Date(timeIntervalSinceReferenceDate: 800_000_100.5)
    private static let t2 = Date(timeIntervalSinceReferenceDate: 800_000_200.25)
    private static let dragonBallCover = "https://cdn.myanimelist.net/images/manga/1/267793l.jpg"

    private static let dragonBall = ReadingItem(
        mangaID: 42,
        title: "Dragon Ball",
        coverURL: dragonBallCover,
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

    private let actor: MangaSyncActor
    private let container: ModelContainer

    init() throws {
        let made = try WatchPersistenceTestSupport.makeActor()
        actor = made.actor
        container = made.container
    }

    // MARK: - Reading snapshot

    @Test func `A snapshot creates every manga and its entry with the item's fields and date, and queues nothing`() async throws {
        try await actor.applyReadingSnapshot(ReadingSnapshot(generatedAt: Self.t0, items: [Self.berserk, Self.dragonBall]))

        let context = WatchPersistenceTestSupport.freshContext(container)
        let dragonBall = try #require(try WatchPersistenceTestSupport.manga(id: 42, in: context))
        #expect(dragonBall.title == "Dragon Ball")
        #expect(dragonBall.mainPictureURL == Self.dragonBallCover)
        #expect(dragonBall.volumes == 42)
        #expect(dragonBall.inCollection)
        #expect(dragonBall.updatedAt == Self.t1)
        let dragonBallEntry = try #require(dragonBall.collectionEntry)
        #expect(dragonBallEntry.mangaID == 42)
        #expect(dragonBallEntry.readingVolume == 7)
        #expect(!dragonBallEntry.completeCollection)
        #expect(dragonBallEntry.updatedAt == Self.t1)

        let berserk = try #require(try WatchPersistenceTestSupport.manga(id: 2, in: context))
        #expect(berserk.title == "Berserk")
        #expect(berserk.mainPictureURL == nil)
        #expect(berserk.volumes == nil)
        #expect(berserk.inCollection)
        #expect(berserk.updatedAt == Self.t2)
        let berserkEntry = try #require(berserk.collectionEntry)
        #expect(berserkEntry.readingVolume == 3)
        #expect(berserkEntry.updatedAt == Self.t2)

        #expect(try WatchPersistenceTestSupport.fetchAll(PendingOperation.self, in: context).isEmpty)
    }

    @Test func `A snapshot updates a stored manga and its entry in place`() async throws {
        try WatchPersistenceTestSupport.insertManga(
            id: 42,
            title: "Doragon Bōru",
            volumes: 40,
            coverURL: nil,
            updatedAt: Self.t0,
            entry: .init(readingVolume: 5, completeCollection: true, updatedAt: Self.t0),
            in: container
        )

        try await actor.applyReadingSnapshot(ReadingSnapshot(generatedAt: Self.t2, items: [Self.dragonBall]))

        #expect(try WatchPersistenceTestSupport.mangaIDs(in: container) == [42])
        #expect(try WatchPersistenceTestSupport.entryMangaIDs(in: container) == [42])
        let context = WatchPersistenceTestSupport.freshContext(container)
        let manga = try #require(try WatchPersistenceTestSupport.manga(id: 42, in: context))
        #expect(manga.title == "Dragon Ball")
        #expect(manga.mainPictureURL == Self.dragonBallCover)
        #expect(manga.volumes == 42)
        #expect(manga.updatedAt == Self.t1)
        let entry = try #require(manga.collectionEntry)
        #expect(entry.readingVolume == 7)
        #expect(!entry.completeCollection)
        #expect(entry.updatedAt == Self.t1)
    }

    @Test func `A snapshot deletes the mangas it no longer lists together with their entries`() async throws {
        try WatchPersistenceTestSupport.insertManga(
            id: 42, volumes: 42, updatedAt: Self.t0, entry: .init(readingVolume: 7, updatedAt: Self.t0), in: container
        )
        try WatchPersistenceTestSupport.insertManga(
            id: 13, volumes: 10, updatedAt: Self.t0, entry: .init(readingVolume: 2, updatedAt: Self.t0), in: container
        )

        try await actor.applyReadingSnapshot(ReadingSnapshot(generatedAt: Self.t2, items: [Self.dragonBall]))

        #expect(try WatchPersistenceTestSupport.mangaIDs(in: container) == [42])
        #expect(try WatchPersistenceTestSupport.entryMangaIDs(in: container) == [42])
    }

    @Test func `Applying the same snapshot three times leaves one manga and one entry per item`() async throws {
        let snapshot = ReadingSnapshot(generatedAt: Self.t0, items: [Self.berserk, Self.dragonBall])

        for _ in 1 ... 3 {
            try await actor.applyReadingSnapshot(snapshot)
        }

        #expect(try WatchPersistenceTestSupport.mangaIDs(in: container) == [2, 42])
        #expect(try WatchPersistenceTestSupport.entryMangaIDs(in: container) == [2, 42])
        let context = WatchPersistenceTestSupport.freshContext(container)
        let entry = try #require(try WatchPersistenceTestSupport.entry(mangaID: 42, in: context))
        #expect(entry.readingVolume == 7)
        #expect(entry.updatedAt == Self.t1)
    }

    @Test func `An empty snapshot empties the store`() async throws {
        try WatchPersistenceTestSupport.insertManga(
            id: 42, volumes: 42, updatedAt: Self.t0, entry: .init(readingVolume: 7, updatedAt: Self.t0), in: container
        )
        try WatchPersistenceTestSupport.insertManga(
            id: 2, volumes: nil, updatedAt: Self.t0, entry: .init(readingVolume: 3, updatedAt: Self.t0), in: container
        )

        try await actor.applyReadingSnapshot(ReadingSnapshot(generatedAt: Self.t1, items: []))

        #expect(try WatchPersistenceTestSupport.mangaIDs(in: container).isEmpty)
        #expect(try WatchPersistenceTestSupport.entryMangaIDs(in: container).isEmpty)
    }

    // MARK: - Local reading volume

    @Test func `A local volume change stamps the entry and the manga with now, returns now and queues nothing`() async throws {
        try WatchPersistenceTestSupport.insertManga(
            id: 42, volumes: 42, updatedAt: Self.t0, entry: .init(readingVolume: 7, updatedAt: Self.t0), in: container
        )

        let changedAt = try await actor.applyLocalReadingVolume(mangaID: 42, readingVolume: 8, now: Self.t2)

        #expect(changedAt == Self.t2)
        let context = WatchPersistenceTestSupport.freshContext(container)
        let manga = try #require(try WatchPersistenceTestSupport.manga(id: 42, in: context))
        #expect(manga.updatedAt == Self.t2)
        let entry = try #require(manga.collectionEntry)
        #expect(entry.readingVolume == 8)
        #expect(entry.updatedAt == Self.t2)
        #expect(try WatchPersistenceTestSupport.fetchAll(PendingOperation.self, in: context).isEmpty)
    }

    @Test func `A local volume above the volume limit is stored as the limit`() async throws {
        try WatchPersistenceTestSupport.insertManga(
            id: 42, volumes: nil, updatedAt: Self.t0, entry: .init(readingVolume: 7, updatedAt: Self.t0), in: container
        )

        _ = try await actor.applyLocalReadingVolume(mangaID: 42, readingVolume: UserCollectionEntry.volumeLimit + 50, now: Self.t2)

        let context = WatchPersistenceTestSupport.freshContext(container)
        let entry = try #require(try WatchPersistenceTestSupport.entry(mangaID: 42, in: context))
        #expect(entry.readingVolume == UserCollectionEntry.volumeLimit)
    }

    @Test(arguments: [true, false])
    func `A local volume change without a collection entry throws notFound and writes nothing`(isMangaStored: Bool) async throws {
        if isMangaStored {
            try WatchPersistenceTestSupport.insertManga(id: 42, volumes: 42, updatedAt: Self.t0, entry: nil, in: container)
        }

        do throws(PersistenceError) {
            _ = try await actor.applyLocalReadingVolume(mangaID: 42, readingVolume: 8, now: Self.t2)
            Issue.record("Expected PersistenceError.notFound, but the change completed")
        } catch {
            switch error {
            case .notFound:
                break
            default:
                Issue.record("Expected PersistenceError.notFound, got \(error)")
            }
        }

        let context = WatchPersistenceTestSupport.freshContext(container)
        #expect(try WatchPersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
        #expect(try WatchPersistenceTestSupport.fetchAll(PendingOperation.self, in: context).isEmpty)
        #expect(try WatchPersistenceTestSupport.mangaIDs(in: container) == (isMangaStored ? [42] : []))
    }
}
