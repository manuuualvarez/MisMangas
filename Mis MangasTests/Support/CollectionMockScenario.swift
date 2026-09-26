//
//  CollectionMockScenario.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas

/// Collection-flavoured façade over the `CatalogMockScenario` slot that `URLSessionMockInterface`
/// serves: `GET /collection/manga`, `POST /collection/manga` and `DELETE /collection/manga/{id}`.
///
/// Suites that use it are nested under `SharedMockSuites`. A test configures each verb with
/// `set(_:_:)` (every call) or `setSequence(_:_:)` (the next calls, one behavior each, e.g.
/// `[.status(201), .status(401)]` for "401 on the second"), runs production code and reads the
/// oracle: the uploaded bodies and deleted ids in the order they reached the wire, the
/// `Authorization` of each request, hit counters and the arrival order across every route.
enum CollectionMockScenario {
    typealias Key = CatalogMockScenario.Key
    typealias Behavior = CatalogMockScenario.Behavior
    typealias CapturedRequest = CatalogMockScenario.CapturedRequest

    /// An empty collection, as `GET /collection/manga` returns it for a new account.
    static let emptyCollection = Behavior.json("[]")

    // MARK: - Configuration

    static func reset() {
        CatalogMockScenario.reset()
    }

    static func set(_ key: Key, _ behavior: Behavior) {
        CatalogMockScenario.set(key, behavior)
    }

    static func setSequence(_ key: Key, _ behaviors: [Behavior]) {
        CatalogMockScenario.setSequence(key, behaviors)
    }

    /// `status` with the backend error body `{"error": true, "reason": …}`.
    static func errorBody(status: Int, reason: String) -> Behavior {
        .json(#"{"error":true,"reason":"\#(reason)"}"#, status: status)
    }

    // MARK: - Ordering

    /// Waits until a request of `key` is held, for passes nobody awaits (started by `requestSync`).
    /// Nothing in the test can end this wait when the code under test never sends the request, so
    /// the test carries a time limit; cancelling the test resets the mock, which ends the wait and
    /// makes this return `false`.
    static func waitUntilHeldOrCancelled(_ key: Key) async -> Bool {
        await withTaskCancellationHandler {
            await CatalogMockScenario.waitUntilHeld(key)
        } onCancel: {
            reset()
        }
        return CatalogMockScenario.isHeld(key)
    }

    // MARK: - Oracle

    static func hits(_ key: Key) -> Int {
        CatalogMockScenario.hits(key)
    }

    static func totalHits() -> Int {
        CatalogMockScenario.totalHits()
    }

    static func arrivals() -> [Key] {
        CatalogMockScenario.arrivals()
    }

    static func requests(_ key: Key) -> [CapturedRequest] {
        CatalogMockScenario.requests(key)
    }

    static func lastRequest(_ key: Key) -> CapturedRequest? {
        CatalogMockScenario.lastRequest(key)
    }

    /// Every `POST /collection/manga` body, in the order the requests reached the wire.
    static func uploadedRequests() throws -> [UserMangaCollectionRequest] {
        try requests(.collectionUpsert).map { try $0.decodedBody(as: UserMangaCollectionRequest.self) }
    }

    /// The manga id of every `POST /collection/manga`, in arrival order.
    static func uploadedMangaIDs() throws -> [Int] {
        try uploadedRequests().map(\.manga)
    }

    /// The id in the path of every `DELETE /collection/manga/{id}`, in arrival order.
    static func deletedMangaIDs() -> [Int] {
        requests(.collectionDelete).compactMap { $0.request.url.flatMap { Int($0.lastPathComponent) } }
    }
}
