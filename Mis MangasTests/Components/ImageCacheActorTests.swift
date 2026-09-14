//
//  ImageCacheActorTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

@testable import Mis_Mangas
import Testing
import UIKit

extension SharedMockSuites {
    /// Cover downloads through `ImageCacheActor` → `ImageDownloader` → mocked `URLSession`.
    /// Oracle: the mock's hit counter for the CDN host and the decoded size of the served PNG.
    @Suite("ImageCacheActor")
    struct ImageCacheActorTests {
        /// A real cover URL from `mangas_page.json` (Monster).
        private static let coverURL: URL = {
            guard let url = URL(string: "https://cdn.myanimelist.net/images/manga/3/258224l.jpg") else {
                preconditionFailure("Invalid cover URL literal")
            }
            return url
        }()

        /// A valid 1×1 RGBA PNG (70 bytes, CRC verified). Its decoded size is the oracle.
        private static let onePixelPNGBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

        init() {
            CatalogMockScenario.reset()
        }

        @Test func `Two concurrent requests for the same URL download it once and both get the image`() async throws {
            let png = try pngBytes()
            // The first download stays in flight long enough for the second request to arrive.
            CatalogMockScenario.set(.image, .delayed(for: .milliseconds(300), then: .data(png, status: 200)))
            let cache = makeCache()

            async let first = cache.image(for: Self.coverURL)
            async let second = cache.image(for: Self.coverURL)
            let (firstImage, secondImage) = await (first, second)

            #expect(CatalogMockScenario.hits(.image) == 1)
            let unwrappedFirst = try #require(firstImage)
            let unwrappedSecond = try #require(secondImage)
            #expect(unwrappedFirst.size == CGSize(width: 1, height: 1))
            #expect(unwrappedSecond.size == CGSize(width: 1, height: 1))
        }

        @Test func `A request after the download completed is served from the cache`() async throws {
            let png = try pngBytes()
            CatalogMockScenario.set(.image, .data(png, status: 200))
            let cache = makeCache()

            let firstImage = await cache.image(for: Self.coverURL)
            let secondImage = await cache.image(for: Self.coverURL)

            #expect(firstImage != nil)
            #expect(secondImage != nil)
            #expect(CatalogMockScenario.hits(.image) == 1)
        }

        @Test(arguments: [
            CatalogMockScenario.Behavior.status(500),
            CatalogMockScenario.Behavior.status(404),
            CatalogMockScenario.Behavior.transportError(.notConnectedToInternet),
            CatalogMockScenario.Behavior.json("not an image", status: 200),
        ])
        func `A failed download yields nil without crashing`(behavior: CatalogMockScenario.Behavior) async {
            CatalogMockScenario.set(.image, behavior)
            let cache = makeCache()

            let image = await cache.image(for: Self.coverURL)

            #expect(image == nil)
            #expect(CatalogMockScenario.hits(.image) == 1)
        }

        // MARK: - Helpers

        private func makeCache() -> ImageCacheActor {
            ImageCacheActor(downloader: ImageDownloader(session: URLSessionMockInterface.makeSession()))
        }

        private func pngBytes() throws -> Data {
            try #require(Data(base64Encoded: Self.onePixelPNGBase64))
        }
    }
}
