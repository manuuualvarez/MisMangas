//
//  ReadingItemsFetcherTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// What the widget reads from the shared store: which mangas count as being read, in which order,
/// how many, and which cached cover each one points to. The store is seeded through a fresh
/// context with dates chosen here; the oracle is the list of items written by hand below and the
/// files the test itself puts in a temporary folder.
@Suite("ReadingItemsFetcher")
struct ReadingItemsFetcherTests {
    private typealias Entry = ReadingListTestSupport.Entry

    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let container: ModelContainer

    init() throws {
        container = try PersistenceController.makeInMemoryContainer()
    }

    /// A manga in the collection reading `readingVolume`, its entry last changed at `t0 + entryOffset`
    /// and the manga itself at `t0 + mangaOffset`.
    private func seedReading(
        id: Int,
        title: String = "Manga",
        readingVolume: Int = 1,
        volumes: Int? = 10,
        entryOffset: TimeInterval,
        mangaOffset: TimeInterval = 0
    ) throws {
        try ReadingListTestSupport.insertManga(
            id: id,
            title: title,
            volumes: volumes,
            updatedAt: Self.t0.addingTimeInterval(mangaOffset),
            entry: Entry(readingVolume: readingVolume, updatedAt: Self.t0.addingTimeInterval(entryOffset)),
            in: container
        )
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ReadingItemsFetcherTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Which mangas, in which order

    @Test
    func `An empty store gives nothing, and a manga being read after that fetch shows up in the next one`() throws {
        let fetcher = ReadingItemsFetcher(container: container, covers: nil)

        let empty = try fetcher.fetch(limit: 6)
        #expect(empty.items.isEmpty)
        #expect(empty.total == 0)

        try seedReading(id: 1, title: "Monster", readingVolume: 3, volumes: 18, entryOffset: 0)
        let seeded = try fetcher.fetch(limit: 6)

        #expect(seeded.items == [
            ReadingWidgetItem(id: 1, title: "Monster", coverFileURL: nil, readingVolume: 3, volumes: 18),
        ])
        #expect(seeded.total == 1)
    }

    @Test
    func `Mangas being read come most recently changed entry first, even when the mangas' own dates say otherwise`() throws {
        try seedReading(id: 1, title: "Monster", readingVolume: 3, volumes: 18, entryOffset: 30, mangaOffset: -300)
        try seedReading(id: 2, title: "Berserk", readingVolume: 5, volumes: nil, entryOffset: 10, mangaOffset: 500)
        try seedReading(id: 3, title: "Dragon Ball", readingVolume: 7, volumes: 42, entryOffset: 20, mangaOffset: -100)

        let result = try ReadingItemsFetcher(container: container, covers: nil).fetch(limit: 6)

        #expect(result.items == [
            ReadingWidgetItem(id: 1, title: "Monster", coverFileURL: nil, readingVolume: 3, volumes: 18),
            ReadingWidgetItem(id: 3, title: "Dragon Ball", coverFileURL: nil, readingVolume: 7, volumes: 42),
            ReadingWidgetItem(id: 2, title: "Berserk", coverFileURL: nil, readingVolume: 5, volumes: nil),
        ])
        #expect(result.total == 3)
    }

    @Test
    func `With ten mangas being read the six most recent are listed and the total counts all ten`() throws {
        for id in 1 ... 10 {
            try seedReading(id: id, entryOffset: TimeInterval(id))
        }

        let result = try ReadingItemsFetcher(container: container, covers: nil).fetch(limit: 6)

        #expect(result.items.map(\.id) == [10, 9, 8, 7, 6, 5])
        #expect(result.total == 10)
    }

    @Test
    func `A complete collection, an entry without a volume being read and an entry without its manga are neither listed nor counted`() throws {
        try seedReading(id: 1, title: "Monster", readingVolume: 3, volumes: 18, entryOffset: 0)
        try ReadingListTestSupport.insertManga(
            id: 2,
            volumes: 7,
            updatedAt: Self.t0,
            entry: Entry(readingVolume: 5, completeCollection: true, updatedAt: Self.t0.addingTimeInterval(10)),
            in: container
        )
        try ReadingListTestSupport.insertManga(
            id: 3,
            volumes: 12,
            updatedAt: Self.t0,
            entry: Entry(readingVolume: nil, volumesOwned: [1, 2], updatedAt: Self.t0.addingTimeInterval(20)),
            in: container
        )
        // A cached manga outside the collection.
        try ReadingListTestSupport.insertManga(id: 4, volumes: 3, updatedAt: Self.t0.addingTimeInterval(40), entry: nil, in: container)
        // The most recent entry of all, being read, but hanging from no manga.
        let context = PersistenceTestSupport.freshContext(container)
        context.insert(UserCollectionEntry(
            mangaID: 99,
            readingVolume: 2,
            createdAt: Self.t0.addingTimeInterval(50),
            updatedAt: Self.t0.addingTimeInterval(50)
        ))
        try context.save()
        let fetcher = ReadingItemsFetcher(container: container, covers: nil)

        let result = try fetcher.fetch(limit: 6)

        #expect(result.items == [
            ReadingWidgetItem(id: 1, title: "Monster", coverFileURL: nil, readingVolume: 3, volumes: 18),
        ])
        #expect(result.total == 1)
        // The entry without a manga is left out before the limit applies, not after.
        #expect(try fetcher.fetch(limit: 1).items.map(\.id) == [1])
    }

    @Test
    func `The last volume being read still counts as reading`() throws {
        try seedReading(id: 1, title: "Dragon Ball", readingVolume: 42, volumes: 42, entryOffset: 0)

        let result = try ReadingItemsFetcher(container: container, covers: nil).fetch(limit: 6)

        #expect(result.items == [
            ReadingWidgetItem(id: 1, title: "Dragon Ball", coverFileURL: nil, readingVolume: 42, volumes: 42),
        ])
        #expect(result.total == 1)
    }

    // MARK: - Covers

    @Test
    func `Only a manga whose cover file exists in the folder points to it`() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let coverFile = directory.appending(path: "1.jpg")
        try Data("cover bytes".utf8).write(to: coverFile)
        try seedReading(id: 1, entryOffset: 20)
        try seedReading(id: 2, entryOffset: 10)

        let items = try ReadingItemsFetcher(container: container, covers: CoverCacheFiles(baseURL: directory)).fetch(limit: 6).items

        try #require(items.map(\.id) == [1, 2])
        #expect(items[0].coverFileURL?.path(percentEncoded: false) == coverFile.path(percentEncoded: false))
        #expect(items[1].coverFileURL == nil)
    }

    @Test
    func `Without a cover folder no manga points to a cover`() throws {
        try seedReading(id: 1, entryOffset: 20)
        try seedReading(id: 2, entryOffset: 10)

        let items = try ReadingItemsFetcher(container: container, covers: nil).fetch(limit: 6).items

        try #require(items.map(\.id) == [1, 2])
        #expect(items.allSatisfy { $0.coverFileURL == nil })
    }

    // MARK: - Presentation

    struct ProgressCase: CustomTestStringConvertible {
        let readingVolume: Int
        let volumes: Int?
        let progress: Double?

        var testDescription: String {
            "volume \(readingVolume) of \(volumes.map(String.init) ?? "unknown")"
        }
    }

    @Test(arguments: [
        ProgressCase(readingVolume: 7, volumes: 42, progress: 7.0 / 42.0),
        ProgressCase(readingVolume: 42, volumes: 42, progress: 1),
        ProgressCase(readingVolume: 1, volumes: 4, progress: 0.25),
        ProgressCase(readingVolume: 7, volumes: nil, progress: nil),
    ])
    func `Progress is the volume being read over the volume count, and unknown without a count`(_ testCase: ProgressCase) {
        let item = ReadingWidgetItem(id: 1, title: "Manga", coverFileURL: nil, readingVolume: testCase.readingVolume, volumes: testCase.volumes)

        #expect(item.progress == testCase.progress)
    }

    @Test
    func `An item links to its manga's detail`() {
        let item = ReadingWidgetItem(id: 42, title: "Dragon Ball", coverFileURL: nil, readingVolume: 7, volumes: 42)

        #expect(item.deepLink.absoluteString == "mismangas://manga/42")
    }
}
