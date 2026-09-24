//
//  CollectionRepositoryAuthRefreshTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

extension SharedMockSuites {
    /// `CollectionRepository` over the real session code (`extension SecurityData` on an
    /// `InMemorySecureStore`): the token each collection request carries is the one the session
    /// renewal leaves in the store. Oracles: the arrival order and headers captured by the mock,
    /// and the store read directly.
    @Suite("CollectionRepository — token renewal")
    struct CollectionRepositoryAuthRefreshTests {
        private let store: InMemorySecureStore
        private let repository: DefaultCollectionRepositoryTest

        init() {
            CollectionMockScenario.reset()
            let store = InMemorySecureStore()
            self.store = store
            repository = DefaultCollectionRepositoryTest(
                security: SecurityTestConformer(store: store, appToken: "test-app-token")
            )
        }

        @Test func `A token with less than 23 h left is renewed before GET collection manga, which carries the new one`() async throws {
            let old = SessionTestTokenFactory.aging()
            let renewed = SessionTestTokenFactory.fresh()
            store.seed(old, key: "jwt")
            store.seed(SessionTestTokenFactory.email, key: "userEmail")
            SessionMockScenario.respondWithToken(.jwtRefresh, renewed)
            CollectionMockScenario.set(.collectionList, .fixture("collection_response.json"))

            let entries = try await repository.fetchCollection()

            #expect(CollectionMockScenario.arrivals() == [.jwtRefresh, .collectionList])
            #expect(SessionMockScenario.authorization(.jwtRefresh) == "Bearer \(old)")
            #expect(CollectionMockScenario.lastRequest(.collectionList)?.header("Authorization") == "Bearer \(renewed)")
            #expect(store.storedString("jwt") == renewed)
            #expect(entries.count == 2)
        }

        @Test func `A fresh token goes straight to the collection without a renewal`() async throws {
            let token = SessionTestTokenFactory.fresh()
            store.seed(token, key: "jwt")
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            _ = try await repository.fetchCollection()

            #expect(CollectionMockScenario.arrivals() == [.collectionList])
            #expect(CollectionMockScenario.lastRequest(.collectionList)?.header("Authorization") == "Bearer \(token)")
        }

        @Test(arguments: [400, 429])
        func `A renewal the server refuses with a status other than 401 is a retryable transport failure, never a refusal`(status: Int) async {
            let old = SessionTestTokenFactory.aging()
            store.seed(old, key: "jwt")
            SessionMockScenario.respondWithError(.jwtRefresh, status: status, reason: "Too many requests")

            await expectAPIError(.transport) {
                try await repository.fetchCollection()
            }

            #expect(CollectionMockScenario.arrivals() == [.jwtRefresh])
            #expect(store.storedString("jwt") == old)
        }

        @Test func `An expired token throws unauthorized, reaches neither refresh nor the collection and is deleted`() async {
            store.seed(SessionTestTokenFactory.expired(), key: "jwt")
            store.seed(SessionTestTokenFactory.email, key: "userEmail")

            await expectAPIError(.unauthorized) {
                try await repository.fetchCollection()
            }

            #expect(CollectionMockScenario.totalHits() == 0)
            #expect(store.storedString("jwt") == nil)
            #expect(store.storedString("userEmail") == SessionTestTokenFactory.email)
        }
    }
}
