//
//  NetworkInteractorTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// Minimal conformer: the only seam is `session`, everything else is the production extension.
private struct TestInteractor: NetworkInteractor {
    let session: URLSession

    nonisolated init() {
        session = URLSessionMockInterface.makeSession()
    }
}

/// A body whose encoding fails: `URLRequest.request` must surface it, never swallow it with `try?`.
private struct Unencodable: Encodable {
    struct Failure: Error {}

    func encode(to encoder: any Encoder) throws {
        throw Failure()
    }
}

extension SharedMockSuites {
    /// Pipeline `URLRequest.request` → `URLSession.getData` → status mapping → `JSONDecoder.app`,
    /// with the transport replaced by `URLSessionMockInterface`. Oracles: fixture content and the
    /// `APIError` mapping of HTTP statuses and transport failures.
    @Suite("NetworkInteractor")
    struct NetworkInteractorTests {
        private let interactor = TestInteractor()

        /// Any routed URL will do; the interactor does not care which endpoint it is.
        private static let detailURL = URLSessionMockInterface.apiBase.appending(path: "search/manga/1")
        /// 1994-12-05T00:00:00Z, computed outside the decoder.
        private static let monsterStart = Date(timeIntervalSince1970: 786_585_600)

        init() {
            CatalogMockScenario.reset()
        }

        // MARK: - Success

        @Test func `A 200 with the Monster fixture decodes a MangaDTO with the app decoder`() async throws {
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))

            let manga = try await interactor.getJSON(request: URLRequest.request(url: Self.detailURL), type: MangaDTO.self)

            #expect(manga.id == 1)
            #expect(manga.title == "Monster")
            #expect(manga.startDate == Self.monsterStart)
            #expect(manga.authors.map(\.lastName) == ["Urasawa"])
        }

        @Test(arguments: [200, 201, 204])
        func `getStatus accepts every 2xx by default`(status: Int) async throws {
            CatalogMockScenario.set(.mangaByID, .status(status))

            try await interactor.getStatus(request: URLRequest.request(url: Self.detailURL))

            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
        }

        // MARK: - Failures

        @Test func `A 200 with invalid JSON throws decoding`() async {
            CatalogMockScenario.set(.mangaByID, .json(#"{ "id": "not-a-number" "#, status: 200))

            await expectAPIError(.decoding) {
                try await interactor.getJSON(request: URLRequest.request(url: Self.detailURL), type: MangaDTO.self)
            }
        }

        @Test(arguments: [
            (401, APIErrorCase.unauthorized),
            (403, APIErrorCase.forbidden),
            (404, APIErrorCase.notFound),
            (500, APIErrorCase.serverError),
            (503, APIErrorCase.serverError),
            (418, APIErrorCase.http(status: 418)),
        ])
        func `getJSON maps HTTP statuses to their APIError case`(status: Int, expected: APIErrorCase) async {
            CatalogMockScenario.set(.mangaByID, .status(status))

            await expectAPIError(expected) {
                try await interactor.getJSON(request: URLRequest.request(url: Self.detailURL), type: MangaDTO.self)
            }
        }

        @Test func `getStatus maps a 404 to notFound`() async {
            CatalogMockScenario.set(.mangaByID, .status(404))

            await expectAPIError(.notFound) {
                try await interactor.getStatus(request: URLRequest.request(url: Self.detailURL))
            }
        }

        @Test func `getStatus honours a custom accepted range`() async {
            CatalogMockScenario.set(.mangaByID, .status(200))

            await expectAPIError(.http(status: 200)) {
                try await interactor.getStatus(request: URLRequest.request(url: Self.detailURL), accepting: 201..<202)
            }
        }

        @Test func `A transport failure maps to transport`() async {
            CatalogMockScenario.set(.mangaByID, .transportError(.notConnectedToInternet))

            let error = await expectAPIError(.transport) {
                try await interactor.getJSON(request: URLRequest.request(url: Self.detailURL), type: MangaDTO.self)
            }

            if case .transport(let underlying) = error {
                #expect((underlying as? URLError)?.code == .notConnectedToInternet)
            }
        }

        @Test func `Cancelling the task while the response is in flight maps to cancelled`() async throws {
            CatalogMockScenario.set(.mangaByID, .delayed(for: .milliseconds(500), then: .fixture("manga_monster.json")))
            let interactor = interactor

            let task = Task {
                try await interactor.getJSON(request: URLRequest.request(url: Self.detailURL), type: MangaDTO.self)
            }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()

            switch await task.result {
            case .success:
                Issue.record("Expected APIError.cancelled, but the request completed")
            case .failure(let error):
                expectAPIError(.cancelled, matches: error)
            }
        }

        @Test func `A body that fails to encode throws encoding`() async {
            await expectAPIError(.encoding) {
                try URLRequest.request(url: Self.detailURL, method: .post, body: Unencodable())
            }
        }
    }
}
