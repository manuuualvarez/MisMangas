//
//  ReadingWidgetServiceTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Synchronization
import Testing

extension SharedMockSuites {
    /// `ReadingWidgetService` over the real `MangaSyncActor` (in-memory store), a real
    /// `SyncCoordinator` whose `MangaSyncService` is a guest's (its passes stay on the device), and
    /// a real `CoverCacheService` writing to a temporary folder through the mocked transport. The
    /// widget reload is a counted closure that also records which covers were on disk when it ran.
    /// The service works on its own task, so every effect is awaited with a bounded wait. Oracles:
    /// the reload count, the covers on disk (read with `FileManager`) and the store seeded here
    /// with dates chosen by hand.
    @Suite("ReadingWidgetService")
    struct ReadingWidgetServiceTests {
        private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

        /// The covers folder's file names each time the widget was asked to reload, in order.
        private final class CoversAtReload: Sendable {
            private let snapshots = Mutex<[Set<String>]>([])

            func record(_ names: Set<String>) {
                snapshots.withLock { $0.append(names) }
            }

            var all: [Set<String>] {
                snapshots.withLock { $0 }
            }
        }

        private let actor: MangaSyncActor
        private let container: ModelContainer
        private let coordinator: SyncCoordinator
        private let directory: URL
        private let reloads = CallCounter()
        private let coversAtReload = CoversAtReload()

        init() throws {
            CatalogMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            actor = made.actor
            container = made.container
            coordinator = SyncCoordinator(service: CollectionTestSupport.makeService(actor: actor, account: nil, security: FakeSecurity()))
            directory = FileManager.default.temporaryDirectory
                .appending(path: "ReadingWidgetServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
                .appending(path: "covers", directoryHint: .isDirectory)
            try CatalogMockScenario.set(.image, .data(CoverTestImage.png(width: 1000, height: 1400)))
        }

        /// The service under test; `hasCoverCache: false` leaves it without a cover cache.
        private func makeService(hasCoverCache: Bool = true) -> ReadingWidgetService {
            let coverCache = hasCoverCache
                ? CoverCacheService(
                    files: CoverCacheFiles(baseURL: directory),
                    downloader: ImageDownloader(session: URLSessionMockInterface.makeSession())
                )
                : nil
            let reloads = reloads
            let coversAtReload = coversAtReload
            let path = directory.path(percentEncoded: false)
            return ReadingWidgetService(
                syncActor: actor,
                syncCoordinator: coordinator,
                coverCache: coverCache,
                reload: {
                    let names = try? FileManager.default.contentsOfDirectory(atPath: path)
                    coversAtReload.record(Set(names ?? []))
                    reloads.increment()
                }
            )
        }

        private func removeDirectory() {
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }

        /// Every file name in the covers folder; empty when the folder is missing.
        private func fileNames() -> Set<String> {
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            return Set(names ?? [])
        }

        /// Waits until the widget has been reloaded `count` times.
        private func waitForReloads(_ count: Int) async -> Bool {
            await AsyncCondition.waitUntil { reloads.value >= count }
        }

        /// Whether the reload count stays at `count` for a while. A correct service never goes past
        /// it, so the wait only ever ends early for a service that reloads too often.
        private func reloadsStay(at count: Int) async -> Bool {
            let wentPast = await AsyncCondition.waitUntil(timeout: .milliseconds(300)) { reloads.value > count }
            return !wentPast && reloads.value == count
        }

        // MARK: - Seeds

        /// A manga with a cover on the CDN the mock serves; in the collection being read when
        /// `readingVolume` is set, its entry last changed at `t0 + entryOffset`.
        private func seed(id: Int, readingVolume: Int?, completeCollection: Bool = false, entryOffset: TimeInterval = 0) throws {
            try ReadingListTestSupport.insertManga(
                id: id,
                title: "Manga \(id)",
                volumes: 10,
                coverURL: "https://cdn.myanimelist.net/images/manga/\(id)/cover.jpg",
                updatedAt: Self.t0,
                entry: ReadingListTestSupport.Entry(
                    readingVolume: readingVolume,
                    completeCollection: completeCollection,
                    updatedAt: Self.t0.addingTimeInterval(entryOffset)
                ),
                in: container
            )
        }

        // MARK: - Start

        @Test(.timeLimit(.minutes(1)))
        func `start reloads the widget once, after writing the covers of the mangas being read`() async throws {
            defer { removeDirectory() }
            try seed(id: 1, readingVolume: 3, entryOffset: 10)
            try seed(id: 2, readingVolume: 5, entryOffset: 20)
            try seed(id: 3, readingVolume: 10, completeCollection: true, entryOffset: 30)
            let service = makeService()

            await service.start()

            try #require(await waitForReloads(1))
            #expect(await reloadsStay(at: 1))
            #expect(coversAtReload.all == [["1.jpg", "2.jpg"]])
            #expect(fileNames() == ["1.jpg", "2.jpg"])
        }

        @Test(.timeLimit(.minutes(1)))
        func `A second start neither reloads again nor doubles the reloads of a pass`() async throws {
            defer { removeDirectory() }
            try seed(id: 1, readingVolume: 3)
            let service = makeService()

            await service.start()
            await service.start()

            try #require(await waitForReloads(1))
            #expect(await reloadsStay(at: 1))
            _ = try await coordinator.synchronize()
            try #require(await waitForReloads(2))
            #expect(await reloadsStay(at: 2))
        }

        @Test(.timeLimit(.minutes(1)))
        func `Without a cover cache the widget is still reloaded`() async throws {
            defer { removeDirectory() }
            try seed(id: 1, readingVolume: 3)
            let service = makeService(hasCoverCache: false)

            await service.start()

            try #require(await waitForReloads(1))
            #expect(CatalogMockScenario.hits(.image) == 0)
            #expect(fileNames().isEmpty)
        }

        @Test(.timeLimit(.minutes(1)))
        func `With eight mangas being read only the six most recent keep a cover`() async throws {
            defer { removeDirectory() }
            for id in 1 ... 8 {
                try seed(id: id, readingVolume: 1, entryOffset: TimeInterval(id))
            }
            let service = makeService()

            await service.start()

            try #require(await waitForReloads(1))
            #expect(fileNames() == ["3.jpg", "4.jpg", "5.jpg", "6.jpg", "7.jpg", "8.jpg"])
            #expect(CatalogMockScenario.hits(.image) == 6)
        }

        // MARK: - Passes

        @Test(.timeLimit(.minutes(1)))
        func `A pass that changes nothing reloads the widget exactly once more`() async throws {
            defer { removeDirectory() }
            try seed(id: 1, readingVolume: 3)
            let service = makeService()
            await service.start()
            // The service follows the passes before its first reload.
            try #require(await waitForReloads(1))

            _ = try await coordinator.synchronize()

            try #require(await waitForReloads(2))
            #expect(await reloadsStay(at: 2))
        }

        @Test(.timeLimit(.minutes(1)))
        func `A manga that starts being read gets its cover on disk before the reload of the pass that follows`() async throws {
            defer { removeDirectory() }
            try seed(id: 1, readingVolume: 3, entryOffset: 10)
            // Stored, outside the collection.
            try ReadingListTestSupport.insertManga(
                id: 2,
                title: "Manga 2",
                volumes: 10,
                coverURL: "https://cdn.myanimelist.net/images/manga/2/cover.jpg",
                updatedAt: Self.t0,
                entry: nil,
                in: container
            )
            let service = makeService()
            await service.start()
            try #require(await waitForReloads(1))

            try await actor.saveCollectionEntry(mangaID: 2, volumesOwned: [], readingVolume: 1, completeCollection: false, account: nil)
            await coordinator.requestSync()

            try #require(await waitForReloads(2))
            #expect(await reloadsStay(at: 2))
            #expect(coversAtReload.all == [["1.jpg"], ["1.jpg", "2.jpg"]])
        }

        @Test(.timeLimit(.minutes(1)))
        func `A manga that stops being read loses its cover in the next pass`() async throws {
            defer { removeDirectory() }
            try seed(id: 1, readingVolume: 3, entryOffset: 10)
            try seed(id: 2, readingVolume: 5, entryOffset: 20)
            let service = makeService()
            await service.start()
            try #require(await waitForReloads(1))
            try #require(fileNames() == ["1.jpg", "2.jpg"])

            try await actor.saveCollectionEntry(mangaID: 1, volumesOwned: [], readingVolume: 10, completeCollection: true, account: nil)
            await coordinator.requestSync()

            try #require(await waitForReloads(2))
            #expect(coversAtReload.all.last == ["2.jpg"])
            #expect(fileNames() == ["2.jpg"])
        }
    }
}
