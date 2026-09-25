//
//  AppDependenciesTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// How the app's single `SyncCoordinator` follows the session: `AppDependencies` over an
    /// in-memory store, with the collection repository's transport replaced by
    /// `URLSessionMockInterface`. Oracles: the requests the mock received (count and order) and the
    /// outbox a fresh `ModelContext` reads afterwards.
    @Suite("AppDependencies")
    @MainActor
    struct AppDependenciesTests {
        private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        /// Any password: the account backend is a `FakeSecurity` that accepts it.
        private static let eightCharacters = "12345678"

        private let dependencies: AppDependencies
        private let container: ModelContainer

        init() throws {
            CollectionMockScenario.reset()
            let container = try PersistenceController.makeInMemoryContainer()
            self.container = container
            dependencies = AppDependencies(
                container: container,
                mangaRepository: DefaultMangaRepositoryTest(),
                security: FakeSecurity(token: "example.dependencies.jwt"),
                collectionRepository: DefaultCollectionRepositoryTest(security: FakeSecurity(token: "example.dependencies.jwt"))
            )
        }

        /// Stores the mangas and queues one upload per id, oldest first.
        private func queueUpserts(_ mangaIDs: [Int]) async throws {
            let actor = dependencies.syncActor
            try await CollectionTestSupport.storeMangas(mangaIDs, in: actor, now: Self.t0)
            for (offset, mangaID) in mangaIDs.enumerated() {
                try await actor.saveCollectionEntry(
                    mangaID: mangaID,
                    volumesOwned: [1],
                    readingVolume: nil,
                    completeCollection: false,
                    now: Self.t0.addingTimeInterval(TimeInterval(offset + 1))
                )
            }
        }

        private func operations() throws -> [PendingOperation] {
            try CollectionTestSupport.operations(in: PersistenceTestSupport.freshContext(container))
        }

        /// Waits until a request of `key` is held. Nothing in the test can end this wait when the
        /// code under test never sends it, so the test carries a time limit; cancelling the test
        /// resets the mock, which ends the wait and lets the caller's `#require` fail.
        private func waitUntilHeldOrCancelled(_ key: CollectionMockScenario.Key) async -> Bool {
            await withTaskCancellationHandler {
                await CatalogMockScenario.waitUntilHeld(key)
            } onCancel: {
                CollectionMockScenario.reset()
            }
            return CatalogMockScenario.isHeld(key)
        }

        @Test func `bootstrap without a session never reaches the collection, and the same queue uploads once the session is applied`() async throws {
            try await queueUpserts([1])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            await dependencies.bootstrap()
            // Waits for any pass bootstrap may have started.
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(CollectionMockScenario.totalHits() == 0)
            #expect(try operations().map(\.mangaID) == [1])

            // Control: the same store and routes do reach the server with a session, so the zero
            // above is the missing session and not the setup.
            await dependencies.applySession(authenticated: true)
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1])
            #expect(try operations().isEmpty)
        }

        @Test(.timeLimit(.minutes(1)))
        func `bootstrap after applying a signed-in session starts a pass that uploads the queue`() async throws {
            try await queueUpserts([1, 2])
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)

            await dependencies.applySession(authenticated: true)
            await dependencies.bootstrap()
            // Nobody asked for a pass but bootstrap: the upload in flight is its pass.
            try #require(await waitUntilHeldOrCancelled(.collectionUpsert))
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            // Joins the running pass (or runs one more over an empty queue) and waits for it.
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1, 2])
            #expect(try operations().isEmpty)
        }

        @Test(.timeLimit(.minutes(1)))
        func `Applying the guest session stops the pass in flight and sends nothing more`() async throws {
            try await queueUpserts([1, 2])
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            await dependencies.applySession(authenticated: true)
            let coordinator = dependencies.syncCoordinator

            let caller = Task { try await coordinator.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: caller))
            await dependencies.applySession(authenticated: false)
            // A pass that was not stopped would carry on from here and upload the rest.
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            _ = await caller.result

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 1)
            #expect(CollectionMockScenario.hits(.collectionList) == 0)
            #expect(try operations().map(\.mangaID) == [1, 2])

            // The guest pass that follows stays on the device.
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(CollectionMockScenario.totalHits() == 1)
            #expect(try operations().map(\.mangaID) == [1, 2])
        }

        @Test(.timeLimit(.minutes(1)))
        func `signOut stops the pass in flight before the session goes away, so nothing more is sent`() async throws {
            try await queueUpserts([1, 2])
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let session = dependencies.session
            await session.signIn(email: "reader@example.com", password: Self.eightCharacters)
            try #require(session.isAuthenticated)
            await dependencies.applySession(authenticated: true)
            let coordinator = dependencies.syncCoordinator

            let caller = Task { try await coordinator.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: caller))
            await session.signOut()
            // A pass that outlived the sign-out would carry on from here and upload the rest.
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            _ = await caller.result

            #expect(session.state == .idle)
            #expect(CollectionMockScenario.hits(.collectionUpsert) == 1)
            #expect(CollectionMockScenario.hits(.collectionList) == 0)
        }
    }
}
