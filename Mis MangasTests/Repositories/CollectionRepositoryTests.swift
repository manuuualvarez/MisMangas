//
//  CollectionRepositoryTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

extension SharedMockSuites {
    /// Every method of `CollectionRepository` through the real pipeline (token → endpoint →
    /// request → transport → status mapping → decode), with the session scripted by
    /// `FakeSecurity`. Oracles: the requests captured by the mock checked against the contract
    /// verified on the live API (verbs, paths, Bearer, body), the content of
    /// `collection_response.json`, and the call counters of the fake.
    @Suite("CollectionRepository")
    struct CollectionRepositoryTests {
        private static let token = "example.collection.token"

        private let security: FakeSecurity
        private let repository: DefaultCollectionRepositoryTest

        init() {
            CollectionMockScenario.reset()
            let security = FakeSecurity(token: Self.token, email: SessionTestTokenFactory.email)
            self.security = security
            repository = DefaultCollectionRepositoryTest(security: security)
        }

        // MARK: - fetchCollection

        @Test func `fetchCollection sends the Bearer token to GET collection manga and decodes both entries with their manga`() async throws {
            CollectionMockScenario.set(.collectionList, .fixture("collection_response.json"))

            let entries = try await repository.fetchCollection()

            let sent = try #require(CollectionMockScenario.lastRequest(.collectionList))
            #expect(sent.method == "GET")
            #expect(sent.path == "/collection/manga")
            #expect(sent.header("Authorization") == "Bearer \(Self.token)")
            #expect(CollectionMockScenario.totalHits() == 1)
            #expect(security.calls(.validToken) == 1)

            #expect(entries.map(\.manga.id) == [1, 2])
            #expect(entries.map(\.manga.title) == ["Monster", "Berserk"])
            #expect(entries.first?.volumesOwned == Array(1...18))
            #expect(entries.first?.readingVolume == 12)
            #expect(entries.last?.readingVolume == nil)
        }

        // MARK: - upsert

        @Test(arguments: [201, 200])
        func `upsert posts the exact body with the Bearer token and accepts any 2xx`(status: Int) async throws {
            CollectionMockScenario.set(.collectionUpsert, .status(status))
            let request = UserMangaCollectionRequest(manga: 42, completeCollection: false, volumesOwned: [1, 2, 5], readingVolume: 2)

            try await repository.upsert(request)

            let sent = try #require(CollectionMockScenario.lastRequest(.collectionUpsert))
            #expect(sent.method == "POST")
            #expect(sent.path == "/collection/manga")
            #expect(sent.header("Authorization") == "Bearer \(Self.token)")
            #expect(sent.header("Content-Type") == "application/json; charset=utf-8")
            #expect(try sent.decodedBody(as: UserMangaCollectionRequest.self) == request)
            #expect(CollectionMockScenario.totalHits() == 1)
        }

        @Test func `upsert of a manga the server does not know surfaces serverError`() async {
            CollectionMockScenario.set(.collectionUpsert, CollectionMockScenario.errorBody(status: 500, reason: "Something went wrong."))

            await expectAPIError(.serverError) {
                try await repository.upsert(UserMangaCollectionRequest(manga: 999_999, completeCollection: false, volumesOwned: [], readingVolume: nil))
            }

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 1)
        }

        // MARK: - delete

        @Test func `delete sends DELETE collection manga id with the Bearer token and accepts a 200`() async throws {
            CollectionMockScenario.set(.collectionDelete, .status(200))

            try await repository.delete(mangaID: 42)

            let sent = try #require(CollectionMockScenario.lastRequest(.collectionDelete))
            #expect(sent.method == "DELETE")
            #expect(sent.path == "/collection/manga/42")
            #expect(sent.header("Authorization") == "Bearer \(Self.token)")
            #expect(CollectionMockScenario.totalHits() == 1)
        }

        @Test func `delete of an entry the server does not have maps the 404 to notFound`() async {
            CollectionMockScenario.set(.collectionDelete, CollectionMockScenario.errorBody(status: 404, reason: "This manga is not at user collection."))

            await expectAPIError(.notFound) {
                try await repository.delete(mangaID: 42)
            }

            #expect(CollectionMockScenario.hits(.collectionDelete) == 1)
        }

        // MARK: - Session failures

        @Test(arguments: [
            (AuthError.sessionExpired, APIErrorCase.unauthorized),
            (AuthError.invalidToken, APIErrorCase.unauthorized),
            (AuthError.invalidCredentials, APIErrorCase.unauthorized),
            (AuthError.offline, APIErrorCase.transport),
            (AuthError.keychain(-25308), APIErrorCase.transport),
            // A failed renewal says nothing about the operation: retryable, never a refusal.
            (AuthError.server(.serverError), APIErrorCase.transport),
            (AuthError.server(.http(status: 429, body: nil)), APIErrorCase.transport),
            (AuthError.server(.cancelled), APIErrorCase.cancelled),
        ])
        func `A session that cannot provide a token maps to its APIError without reaching the collection`(failure: AuthError, expected: APIErrorCase) async {
            security.configure { $0.validTokenError = failure }

            await expectAPIError(expected) {
                try await repository.fetchCollection()
            }

            #expect(security.calls(.validToken) == 1)
            #expect(CollectionMockScenario.totalHits() == 0)
        }

        @Test func `The offline translation carries notConnectedToInternet`() async {
            security.configure { $0.validTokenError = .offline }

            let error = await expectAPIError(.transport) {
                try await repository.fetchCollection()
            }

            if case .transport(let underlying) = error {
                #expect((underlying as? URLError)?.code == .notConnectedToInternet)
            }
        }

        @Test func `Without a stored token upsert and delete send nothing and throw unauthorized`() async {
            security.configure { $0.token = nil }

            await expectAPIError(.unauthorized) {
                try await repository.upsert(UserMangaCollectionRequest(manga: 1, completeCollection: true, volumesOwned: [1], readingVolume: nil))
            }
            await expectAPIError(.unauthorized) {
                try await repository.delete(mangaID: 1)
            }

            #expect(security.calls(.validToken) == 2)
            #expect(CollectionMockScenario.totalHits() == 0)
        }
    }
}
