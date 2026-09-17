//
//  CatalogMockScenario.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Synchronization

/// Per-test routing table, hit counter and request capture for `URLSessionMockInterface`.
///
/// One global `Mutex`-protected slot is enough because every suite that touches the mock is
/// nested under `SharedMockSuites` (`.serialized`). Each test starts with `reset()`, sets the
/// behavior of the endpoints it will hit with `set(_:_:)`, exercises production code, and then
/// reads the oracle: `hits(_:)` (how many times the wire was touched) and `lastRequest(_:)`
/// (the real `URLRequest` production emitted, including the body sent over the wire).
///
/// A key without a configured behavior answers `unroutedStatus` (599): a test that forgot to
/// route an endpoint fails with `APIError.http(status: 599)` instead of silently succeeding.
enum CatalogMockScenario {
    /// Endpoint family, matched by `URLSessionMockInterface` from `(httpMethod, path segments)`.
    /// Names follow the backend routes.
    enum Key: Hashable {
        case listMangas
        case listBestMangas
        case mangaByGenre
        case mangaByTheme
        case mangaByDemographic
        case mangaByAuthor
        case listGenres
        case listThemes
        case listDemographics
        case listAuthorsPaged
        case authorsByIds
        case searchAuthor
        case mangaByID
        case mangasBeginsWith
        case mangasContains
        case customSearch
        /// Cover downloads (`cdn.myanimelist.net`, the CDN every fixture points to).
        case image
        /// A path on the API host that no other key recognises.
        case unmatched
    }

    /// What the mock replies for a matched key. `Sendable` is explicit because an `indirect` enum
    /// gets no implicit inference.
    enum Behavior: Sendable {
        /// 200 with the bytes of `Mis MangasTests/Resources/<fileName>` (e.g. `"mangas_page.json"`).
        case fixture(String)
        /// `status` with an inline JSON literal as body.
        case json(String, status: Int = 200)
        /// `status` with raw bytes as body (covers, deliberately broken payloads).
        case data(Data, status: Int = 200)
        /// `status` with an empty body.
        case status(Int)
        /// The load fails with `URLError(code)` before any response is delivered.
        case transportError(URLError.Code)
        /// Keeps the response in flight for `duration`, then applies `then`. The hit is recorded
        /// before the delay, so `hits(_:)` reflects "the wire was touched" immediately.
        indirect case delayed(for: Duration, then: Behavior)
    }

    /// A request exactly as `URLSession` handed it to the mock, plus the drained body.
    struct CapturedRequest {
        let request: URLRequest
        let body: Data?

        var method: String? {
            request.httpMethod
        }

        /// Percent-decoded path (`/list/mangaByGenre/Slice of Life`).
        var path: String? {
            request.url?.path(percentEncoded: false)
        }

        /// Query as `[name: value]`; empty when the URL has no query.
        var queryValues: [String: String] {
            guard let url = request.url,
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
                return [:]
            }
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        }

        func header(_ name: String) -> String? {
            request.value(forHTTPHeaderField: name)
        }

        struct MissingBody: Error, CustomStringConvertible {
            var description: String {
                "The captured request carried no body"
            }
        }

        /// Decodes the body production put on the wire with the app decoder.
        func decodedBody<Body: Decodable>(as type: Body.Type) throws -> Body {
            guard let body else {
                throw MissingBody()
            }
            return try JSONDecoder.app.decode(type, from: body)
        }
    }

    /// Status answered for keys with no configured behavior.
    static let unroutedStatus = 599

    private struct State {
        var routes: [Key: Behavior] = [:]
        var hits: [Key: Int] = [:]
        var captured: [Key: [CapturedRequest]] = [:]
    }

    private static let state = Mutex(State())

    // MARK: - Configuration

    /// Clears routes, hit counters and captured requests. Called at the start of every test.
    static func reset() {
        state.withLock { $0 = State() }
    }

    static func set(_ key: Key, _ behavior: Behavior) {
        state.withLock { $0.routes[key] = behavior }
    }

    static func set(_ routes: [Key: Behavior]) {
        state.withLock { $0.routes.merge(routes, uniquingKeysWith: { _, new in new }) }
    }

    /// Read by `URLSessionMockInterface` from inside `startLoading`.
    static func behavior(for key: Key) -> Behavior {
        state.withLock { $0.routes[key] ?? .status(unroutedStatus) }
    }

    // MARK: - Recording (mock side)

    static func record(_ key: Key, request: URLRequest, body: Data?) {
        state.withLock {
            $0.hits[key, default: 0] += 1
            $0.captured[key, default: []].append(CapturedRequest(request: request, body: body))
        }
    }

    // MARK: - Oracle (test side)

    static func hits(_ key: Key) -> Int {
        state.withLock { $0.hits[key] ?? 0 }
    }

    static func requests(_ key: Key) -> [CapturedRequest] {
        state.withLock { $0.captured[key] ?? [] }
    }

    static func lastRequest(_ key: Key) -> CapturedRequest? {
        state.withLock { $0.captured[key]?.last }
    }
}
