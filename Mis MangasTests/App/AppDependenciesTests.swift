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
    ///
    /// A class only for `deinit`, which removes the `UserDefaults` suite where the session keeps the
    /// guest choice.
    @Suite("AppDependencies")
    @MainActor
    final class AppDependenciesTests {
        private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        /// Any password: the account backend is a `FakeSecurity` that accepts it.
        private static let eightCharacters = "12345678"

        private let dependencies: AppDependencies
        private let container: ModelContainer
        /// The account backend of both the session and the collection repository, as in the app: a
        /// sign-in changes the token every later request presents.
        private let security: FakeSecurity
        private let suiteName: String

        init() throws {
            CollectionMockScenario.reset()
            let suiteName = "AppDependenciesTests.\(UUID().uuidString)"
            self.suiteName = suiteName
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            let container = try PersistenceController.makeInMemoryContainer()
            self.container = container
            let security = FakeSecurity(token: "example.dependencies.jwt")
            self.security = security
            dependencies = AppDependencies(
                container: container,
                mangaRepository: DefaultMangaRepositoryTest(),
                security: security,
                collectionRepository: DefaultCollectionRepositoryTest(security: security),
                defaults: defaults
            )
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        /// Stores the mangas and queues one upload per id, oldest first, made as a guest.
        private func queueUpserts(_ mangaIDs: [Int]) async throws {
            let actor = dependencies.syncActor
            try await CollectionTestSupport.storeMangas(mangaIDs, in: actor, now: Self.t0)
            for (offset, mangaID) in mangaIDs.enumerated() {
                try await actor.saveCollectionEntry(
                    mangaID: mangaID,
                    volumesOwned: [1],
                    readingVolume: nil,
                    completeCollection: false,
                    account: nil,
                    now: Self.t0.addingTimeInterval(TimeInterval(offset + 1))
                )
            }
        }

        private func operations() throws -> [PendingOperation] {
            try CollectionTestSupport.operations(in: PersistenceTestSupport.freshContext(container))
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
            await dependencies.applySession(account: CollectionTestSupport.account)
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

            await dependencies.applySession(account: CollectionTestSupport.account)
            await dependencies.bootstrap()
            // Nobody asked for a pass but bootstrap: the upload in flight is its pass.
            try #require(await CollectionMockScenario.waitUntilHeldOrCancelled(.collectionUpsert))
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
            await dependencies.applySession(account: CollectionTestSupport.account)
            let coordinator = dependencies.syncCoordinator

            let caller = Task { try await coordinator.synchronize() }
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: caller))
            await dependencies.applySession(account: nil)
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
            await dependencies.applySession(account: session.account)
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

        @Test func `A pass right after signOut, before the signed-out session is applied, stays on the device`() async throws {
            try await CollectionTestSupport.storeMangas([1], in: dependencies.syncActor, now: Self.t0)
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let session = dependencies.session
            await session.signIn(email: "reader@example.com", password: Self.eightCharacters)
            try #require(session.isAuthenticated)
            await dependencies.applySession(account: session.account)

            await session.signOut()
            try #require(session.state == .idle)
            // Nothing applies the signed-out session here: the view has not reacted yet. A change
            // saved in that gap waits in the queue like any change saved without a session.
            try await dependencies.syncService.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: session.account)
            try #require(try operations().map(\.mangaID) == [1])

            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(CollectionMockScenario.totalHits() == 0)
            #expect(try operations().map(\.mangaID) == [1])
        }

        // MARK: - The account that owns the queue

        private static let accountA = "a@example.com"
        private static let accountB = "b@example.com"
        private static let tokenA = "example.token.a"
        private static let tokenB = "example.token.b"
        /// The token of A's second session.
        private static let tokenAAgain = "example.token.a.again"

        /// Signs in as `email`, whose session presents `token` from then on, and follows the change
        /// as the root view does: applies the session, then bootstraps.
        private func signIn(_ email: String, presenting token: String) async throws {
            security.configure { $0.issuedToken = token }
            let session = dependencies.session
            await session.signIn(email: email, password: Self.eightCharacters)
            try #require(session.isAuthenticated)
            await dependencies.applySession(account: session.account)
            await dependencies.bootstrap()
        }

        /// Ends the session as a rejected token does, and follows the change as the root view does.
        private func expireSession() async throws {
            let session = dependencies.session
            await session.expire()
            try #require(!session.isAuthenticated)
            await dependencies.applySession(account: session.account)
            await dependencies.bootstrap()
        }

        /// Saves each manga as the screens do: on the device, under the account of the session at
        /// this moment, without asking for a pass (as when there is no connection).
        private func save(_ mangaIDs: [Int]) async throws {
            try await CollectionTestSupport.storeMangas(mangaIDs, in: dependencies.syncActor, now: Self.t0)
            for mangaID in mangaIDs {
                try await dependencies.syncService.saveCollectionEntry(
                    mangaID: mangaID,
                    volumesOwned: [1],
                    readingVolume: nil,
                    completeCollection: false,
                    account: dependencies.session.account
                )
            }
        }

        /// The `Authorization` of the last request of `key`.
        private func lastAuthorization(_ key: CollectionMockScenario.Key) -> String? {
            CollectionMockScenario.lastRequest(key)?.header("Authorization")
        }

        /// The `Authorization` of every request of `key`, in arrival order.
        private func authorizations(_ key: CollectionMockScenario.Key) -> [String?] {
            CollectionMockScenario.requests(key).map { $0.header("Authorization") }
        }

        @Test(.timeLimit(.minutes(1)))
        func `A guest's three saves are uploaded by the pass that follows signing in`() async throws {
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let session = dependencies.session
            session.continueAsGuest()
            await dependencies.applySession(account: session.account)
            await dependencies.bootstrap()
            try await save([1, 2, 3])

            try await signIn(Self.accountA, presenting: Self.tokenA)
            // Nobody asked for a pass but the bootstrap that follows the sign-in.
            try #require(await CollectionMockScenario.waitUntilHeldOrCancelled(.collectionUpsert))
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1, 2, 3])
            #expect(authorizations(.collectionUpsert) == [String?](repeating: "Bearer \(Self.tokenA)", count: 3))
            #expect(try operations().isEmpty)
        }

        @Test func `The pending changes of an account whose session expired are never uploaded by the next account`() async throws {
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await signIn(Self.accountA, presenting: Self.tokenA)
            _ = try await dependencies.syncCoordinator.synchronize()
            try await save([1, 2])
            try await expireSession()

            try await signIn(Self.accountB, presenting: Self.tokenB)
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)
            // The next account's passes did run: they only had nothing of theirs to send.
            #expect(lastAuthorization(.collectionList) == "Bearer \(Self.tokenB)")
            #expect(try operations().isEmpty)
        }

        @Test(.timeLimit(.minutes(1)))
        func `A pass of the expired account held in flight sends nothing more once the next account signs in`() async throws {
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await signIn(Self.accountA, presenting: Self.tokenA)
            _ = try await dependencies.syncCoordinator.synchronize()
            try await save([1, 2])
            CollectionMockScenario.setSequence(.collectionUpsert, [.held])
            let coordinator = dependencies.syncCoordinator

            let caller = Task { try await coordinator.synchronize() }
            // A's pass took both changes and waits for the server with the first one.
            try #require(await CatalogMockScenario.waitUntilHeld(.collectionUpsert, orUntilFinished: caller))
            try await expireSession()
            // A pass that was not stopped would carry on from here and upload the rest.
            CatalogMockScenario.release(.collectionUpsert, with: .status(201))
            _ = await caller.result
            try await signIn(Self.accountB, presenting: Self.tokenB)
            _ = try await dependencies.syncCoordinator.synchronize()

            // Only the upload that was already on its way while A's session was valid.
            #expect(authorizations(.collectionUpsert) == ["Bearer \(Self.tokenA)"])
            #expect(lastAuthorization(.collectionList) == "Bearer \(Self.tokenB)")
            #expect(try operations().isEmpty)
        }

        @Test func `The pending changes left by an account whose token expired before launch are never uploaded by the account that signs in`() async throws {
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            // An earlier launch left A's session, which the server no longer renews, and two of A's changes.
            let actor = dependencies.syncActor
            try await CollectionTestSupport.storeMangas([1, 2], in: actor, now: Self.t0)
            for mangaID in [1, 2] {
                try await actor.saveCollectionEntry(
                    mangaID: mangaID,
                    volumesOwned: [1],
                    readingVolume: nil,
                    completeCollection: false,
                    account: Self.accountA,
                    now: Self.t0.addingTimeInterval(TimeInterval(mangaID))
                )
            }
            security.configure {
                $0.token = "example.token.a.expired"
                $0.email = Self.accountA
                $0.refreshError = .sessionExpired
            }
            let session = dependencies.session
            await session.restoreSession()
            try #require(session.state == .idle)
            await dependencies.applySession(account: session.account)
            await dependencies.bootstrap()

            try await signIn(Self.accountB, presenting: Self.tokenB)
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)
            #expect(lastAuthorization(.collectionList) == "Bearer \(Self.tokenB)")
            #expect(try operations().isEmpty)
        }

        @Test func `A change made as one account that reaches the store after its sign-out emptied the queue is never uploaded by the next account`() async throws {
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await signIn(Self.accountA, presenting: Self.tokenA)
            _ = try await dependencies.syncCoordinator.synchronize()
            let session = dependencies.session
            // Read when the user tapped Save, while A was signed in.
            let accountAtTheGesture = session.account

            await session.signOut()
            try #require(session.state == .idle)
            // Stored after the sign-in's maintenance, which purges cached mangas outside the collection.
            try await CollectionTestSupport.storeMangas([1], in: dependencies.syncActor, now: Self.t0)
            try await dependencies.syncService.saveCollectionEntry(
                mangaID: 1,
                volumesOwned: [1],
                readingVolume: nil,
                completeCollection: false,
                account: accountAtTheGesture
            )
            try #require(try operations().map(\.mangaID) == [1])
            await dependencies.applySession(account: session.account)
            await dependencies.bootstrap()
            try await signIn(Self.accountB, presenting: Self.tokenB)
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(CollectionMockScenario.hits(.collectionUpsert) == 0)
            #expect(lastAuthorization(.collectionList) == "Bearer \(Self.tokenB)")
            #expect(try operations().isEmpty)
        }

        @Test func `An account that signs in again after its session expired uploads its pending changes, whatever the case of the address`() async throws {
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            try await signIn(Self.accountA, presenting: Self.tokenA)
            _ = try await dependencies.syncCoordinator.synchronize()
            try await save([1, 2])
            try await expireSession()

            try await signIn("A@Example.com", presenting: Self.tokenAAgain)
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(try CollectionMockScenario.uploadedMangaIDs() == [1, 2])
            #expect(authorizations(.collectionUpsert) == ["Bearer \(Self.tokenAAgain)", "Bearer \(Self.tokenAAgain)"])
            #expect(try operations().isEmpty)
        }

        @Test func `Continuing as a guest never reaches the collection on the server and keeps the saves queued as the guest's`() async throws {
            CollectionMockScenario.set(.collectionUpsert, .status(201))
            CollectionMockScenario.set(.collectionList, CollectionMockScenario.emptyCollection)
            let session = dependencies.session
            session.continueAsGuest()
            await dependencies.applySession(account: session.account)
            await dependencies.bootstrap()

            try await save([1])
            _ = try await dependencies.syncCoordinator.synchronize()

            #expect(CollectionMockScenario.totalHits() == 0)
            let queued = try operations()
            #expect(queued.map(\.mangaID) == [1])
            #expect(queued.map(\.account) == [nil])
        }
    }
}
