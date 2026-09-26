//
//  CollectionViewModelDeepLinkTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// A link to a manga, prepared by the collection before it opens the detail: the real pipeline
    /// ViewModel → `MangaSyncService` → `MangaSyncActor` for a stored manga, and → mocked transport
    /// → decode → actor → store for a missing one. The session is a guest one and the coordinator
    /// runs the device-only service, so nothing but the manga request ever reaches the mock.
    ///
    /// Oracles: the requests the mock received (count and path), the literal title of
    /// `manga_monster.json`, the status each failure was answered with, and what a fresh
    /// `ModelContext` reads afterwards.
    @Suite("CollectionViewModel — deep link")
    @MainActor
    struct CollectionViewModelDeepLinkTests {
        /// Monster (id 1) as `/search/manga/1` serves it.
        private static let monsterID = 1
        private static let monsterTitle = "Monster"

        private let viewModel: CollectionViewModel
        private let actor: MangaSyncActor
        private let container: ModelContainer

        init() throws {
            CatalogMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            actor = made.actor
            container = made.container
            let security = FakeSecurity()
            let service = CollectionTestSupport.makeService(actor: made.actor, account: nil, security: security)
            let coordinator = SyncCoordinator(service: service)
            // Nothing here signs in or out, so the session never writes to these defaults.
            let defaults = try #require(UserDefaults(suiteName: "CollectionViewModelDeepLinkTests.\(UUID().uuidString)"))
            let session = SessionViewModel(
                security: security,
                syncCoordinator: coordinator,
                syncActor: made.actor,
                defaults: defaults,
                makeSyncService: { [actor = made.actor] account in
                    CollectionTestSupport.makeService(actor: actor, account: account, security: security)
                }
            )
            viewModel = CollectionViewModel(syncService: service, syncCoordinator: coordinator, session: session)
        }

        /// The manga a fresh context reads for Monster right now.
        private func storedMonster() throws -> Manga? {
            try PersistenceTestSupport.manga(id: Self.monsterID, in: PersistenceTestSupport.freshContext(container))
        }

        // MARK: - Stored manga

        @Test func `A manga already in the store is ready without asking the server`() async throws {
            _ = try await actor.cacheDetail(CollectionTestSupport.monster())
            // Routed, so a request would succeed and could only be told apart by the hit counter.
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))

            let isReady = await viewModel.prepareDeepLinkedManga(id: Self.monsterID)

            #expect(isReady)
            #expect(CatalogMockScenario.totalHits() == 0)
            #expect(viewModel.deepLinkError == nil)
            #expect(!viewModel.isDeepLinkErrorPresented)
        }

        // MARK: - Missing manga

        @Test func `A manga missing from the store is requested by id once and stored before it is reported ready`() async throws {
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))
            try #require(try storedMonster() == nil)

            let isReady = await viewModel.prepareDeepLinkedManga(id: Self.monsterID)

            #expect(isReady)
            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            #expect(CatalogMockScenario.totalHits() == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByID))
            #expect(sent.method == "GET")
            #expect(sent.path == "/search/manga/1")
            let stored = try #require(try storedMonster())
            #expect(stored.title == Self.monsterTitle)
            #expect(viewModel.deepLinkError == nil)
            #expect(!viewModel.isDeepLinkErrorPresented)
        }

        @Test(arguments: [
            (.status(500), .serverError),
            (.status(404), .notFound),
            (.transportError(.notConnectedToInternet), .transport),
        ] as [(CatalogMockScenario.Behavior, APIErrorCase)])
        func `A failed request for a missing manga is shown with its error and the link does not open`(
            response: CatalogMockScenario.Behavior,
            expected: APIErrorCase
        ) async throws {
            CatalogMockScenario.set(.mangaByID, response)

            let isReady = await viewModel.prepareDeepLinkedManga(id: Self.monsterID)

            #expect(!isReady)
            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            let error = try #require(viewModel.deepLinkError)
            #expect(expected.matches(error), "Expected APIError.\(expected), got \(error)")
            #expect(viewModel.isDeepLinkErrorPresented)
            #expect(try storedMonster() == nil)
        }

        // MARK: - Cancellation

        @Test(.timeLimit(.minutes(1)))
        func `Cancelling the link while its request is in flight does not open it and shows no error`() async throws {
            CatalogMockScenario.set(.mangaByID, .held)
            let viewModel = viewModel
            let preparation = Task {
                await viewModel.prepareDeepLinkedManga(id: Self.monsterID)
            }
            // The request reached the wire, so what follows is the cancelled path and not a
            // preparation that never asked the server.
            let isInFlight = await CatalogMockScenario.waitUntilHeld(.mangaByID, orUntilFinished: preparation)
            try #require(isInFlight)

            preparation.cancel()
            let isReady = await preparation.value

            #expect(!isReady)
            #expect(CatalogMockScenario.hits(.mangaByID) == 1)
            #expect(viewModel.deepLinkError == nil)
            #expect(!viewModel.isDeepLinkErrorPresented)
            #expect(try storedMonster() == nil)
        }
    }
}
