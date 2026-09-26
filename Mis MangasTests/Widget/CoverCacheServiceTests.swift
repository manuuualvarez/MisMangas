//
//  CoverCacheServiceTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

extension SharedMockSuites {
    /// `CoverCacheService` over a temporary folder of its own per test, downloading through the
    /// mocked transport, which serves a 1000×1400 PNG made in the test. Oracles: the files in the
    /// folder read back with `FileManager` and ImageIO, and how many cover requests reached the
    /// mock.
    @Suite("CoverCacheService")
    struct CoverCacheServiceTests {
        /// The longest side, in pixels, a cached cover may have.
        private static let maxPixelSide = 560

        private let directory: URL
        private let cache: CoverCacheService
        private let png: Data

        init() throws {
            CatalogMockScenario.reset()
            // Not created here: the service must create it.
            directory = FileManager.default.temporaryDirectory
                .appending(path: "CoverCacheServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
                .appending(path: "covers", directoryHint: .isDirectory)
            cache = CoverCacheService(
                files: CoverCacheFiles(baseURL: directory),
                downloader: ImageDownloader(session: URLSessionMockInterface.makeSession())
            )
            png = try CoverTestImage.png(width: 1000, height: 1400)
        }

        private func removeDirectory() {
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }

        /// A manga being read whose cover lives on the CDN the mock serves.
        private static func item(_ mangaID: Int, hasCover: Bool = true) -> ReadingItem {
            ReadingItem(
                mangaID: mangaID,
                title: "Manga \(mangaID)",
                coverURL: hasCover ? "https://cdn.myanimelist.net/images/manga/\(mangaID)/cover.jpg" : nil,
                readingVolume: 1,
                volumes: 10,
                completeCollection: false,
                updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
            )
        }

        /// Every file name in the folder, hidden ones included; empty when the folder is missing.
        private func fileNames() -> Set<String> {
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            return Set(names ?? [])
        }

        private func coverFile(_ mangaID: Int) -> URL {
            directory.appending(path: "\(mangaID).jpg")
        }

        private func isDirectory(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }

        // MARK: - Writing

        @Test
        func `A missing folder is created`() async {
            defer { removeDirectory() }
            CatalogMockScenario.set(.image, .data(png))

            await cache.update(to: [Self.item(1)])

            #expect(isDirectory(directory))
        }

        @Test
        func `Each cover is written as a readable JPEG no larger than the widget needs`() async throws {
            defer { removeDirectory() }
            CatalogMockScenario.set(.image, .data(png))

            await cache.update(to: [Self.item(1), Self.item(2)])

            #expect(fileNames() == ["1.jpg", "2.jpg"])
            for mangaID in [1, 2] {
                let size = try #require(CoverTestImage.jpegPixelSize(at: coverFile(mangaID)))
                #expect(size.longerSide <= Self.maxPixelSide)
            }
            #expect(CatalogMockScenario.hits(.image) == 2)
        }

        @Test
        func `Updating to the same list again downloads nothing`() async {
            defer { removeDirectory() }
            CatalogMockScenario.set(.image, .data(png))
            await cache.update(to: [Self.item(1), Self.item(2)])
            let firstHits = CatalogMockScenario.hits(.image)

            await cache.update(to: [Self.item(1), Self.item(2)])

            #expect(firstHits == 2)
            #expect(CatalogMockScenario.hits(.image) == firstHits)
            #expect(fileNames() == ["1.jpg", "2.jpg"])
        }

        // MARK: - Deleting

        @Test
        func `A manga that leaves the list loses its cover`() async throws {
            defer { removeDirectory() }
            CatalogMockScenario.set(.image, .data(png))
            await cache.update(to: [Self.item(1), Self.item(2)])
            try #require(fileNames() == ["1.jpg", "2.jpg"])

            await cache.update(to: [Self.item(2)])

            #expect(fileNames() == ["2.jpg"])
        }

        // MARK: - Failures

        @Test
        func `A cover the server does not find leaves no file, not even a temporary one, and the next cover is still written`() async {
            defer { removeDirectory() }
            // Downloads go one at a time, in the order of the items.
            CatalogMockScenario.setSequence(.image, [.status(404), .data(png)])

            await cache.update(to: [Self.item(1), Self.item(2)])

            #expect(fileNames() == ["2.jpg"])
            #expect(CoverTestImage.jpegPixelSize(at: coverFile(2)) != nil)
        }

        @Test
        func `Bytes that are not an image leave no file, and the next cover is still written`() async {
            defer { removeDirectory() }
            CatalogMockScenario.setSequence(.image, [.data(Data("not an image".utf8)), .data(png)])

            await cache.update(to: [Self.item(1), Self.item(2)])

            #expect(fileNames() == ["2.jpg"])
            #expect(CoverTestImage.jpegPixelSize(at: coverFile(2)) != nil)
        }

        @Test
        func `A manga without a cover address is neither requested nor written`() async {
            defer { removeDirectory() }
            CatalogMockScenario.set(.image, .data(png))

            await cache.update(to: [Self.item(1, hasCover: false), Self.item(2)])

            #expect(CatalogMockScenario.hits(.image) == 1)
            #expect(CatalogMockScenario.lastRequest(.image)?.path == "/images/manga/2/cover.jpg")
            #expect(fileNames() == ["2.jpg"])
        }
    }
}
