//
//  CatalogMockScenario.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Synchronization
import Testing

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
///
/// Ordering responses: a key set to `.held` keeps its requests in flight until the test decides.
/// `waitUntilHeld(_:)` returns once one of them reached the mock, and `release(_:with:)` answers
/// the oldest one with the behavior chosen at that moment, so a test fixes the order in which
/// responses land without sleeping.
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
    // swiftformat:disable:next redundantSendable
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
        /// Keeps the response in flight until the test calls `release(_:with:)` for the key,
        /// without blocking the mock thread, so other requests keep being answered meanwhile.
        /// The hit is recorded when the request arrives. A request its consumer cancelled first
        /// is never answered.
        case held
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

    /// A request answered with `.held`, waiting in its key's queue for `release(_:with:)`.
    /// The protocol instance itself never leaves the thread that loads it: it waits in that
    /// thread's dictionary under `token`, and the answer is scheduled on that thread's run loop.
    private struct HeldRequest {
        let token: String
        let runLoop: CFRunLoop
        /// The mode the loading thread was running in, plus the default one: the answer runs as
        /// soon as the loop spins in either, never waiting for one mode to come back.
        let modes: [RunLoop.Mode]
        /// Set by `stopLoading`: the consumer went away, so a release answers nothing.
        var isCancelled = false
    }

    private struct State {
        var routes: [Key: Behavior] = [:]
        var hits: [Key: Int] = [:]
        var captured: [Key: [CapturedRequest]] = [:]
        /// Held requests per key, oldest first.
        var held: [Key: [HeldRequest]] = [:]
        /// Tests suspended in `waitUntilHeld(_:)`, resumed when a request of their key is held.
        var heldWaiters: [Key: [CheckedContinuation<Void, Never>]] = [:]
    }

    private static let state = Mutex(State())

    // MARK: - Configuration

    /// Clears routes, hit counters, captured and held requests. Called at the start of every
    /// test. Requests still held are failed as cancelled so no load stays open across tests, and
    /// any `waitUntilHeld(_:)` still suspended returns instead of hanging.
    static func reset() {
        let waiters = state.withLock { state in
            for request in state.held.values.joined() where !request.isCancelled {
                schedule(request, answering: .transportError(.cancelled))
            }
            let waiters = Array(state.heldWaiters.values.joined())
            state = State()
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
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

    /// Queues a `.held` request. Called by `URLSessionMockInterface` from `startLoading`, on the
    /// thread whose run loop will receive the answer, after it parked itself under `token`.
    static func hold(_ key: Key, token: String) {
        let waiters = state.withLock { state in
            let runLoop = RunLoop.current
            let mode = runLoop.currentMode ?? .default
            let modes = mode == .default ? [mode] : [mode, .default]
            state.held[key, default: []].append(HeldRequest(token: token, runLoop: runLoop.getCFRunLoop(), modes: modes))
            return state.heldWaiters.removeValue(forKey: key) ?? []
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Called by `URLSessionMockInterface` from `stopLoading`: the consumer cancelled the load.
    static func cancelHeld(token: String) {
        state.withLock { state in
            for key in state.held.keys {
                guard let index = state.held[key]?.firstIndex(where: { $0.token == token }) else {
                    continue
                }
                state.held[key]?[index].isCancelled = true
                return
            }
        }
    }

    /// Runs the answer on the loading thread: `URLProtocol` talks to its client from there.
    private static func schedule(_ request: HeldRequest, answering behavior: Behavior) {
        let token = request.token
        CFRunLoopPerformBlock(request.runLoop, request.modes.map(\.rawValue) as CFArray) {
            URLSessionMockInterface.deliverHeld(token: token, behavior: behavior)
        }
        CFRunLoopWakeUp(request.runLoop)
    }

    // MARK: - Ordering (test side)

    /// Returns once a request of `key` answered with `.held` has reached the mock and waits in
    /// its queue with its consumer still there; immediately if one already does. Also returns
    /// when `reset()` runs.
    static func waitUntilHeld(_ key: Key) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isHeld = state.withLock { state in
                if state.held[key]?.contains(where: { !$0.isCancelled }) == true {
                    return true
                }
                state.heldWaiters[key, default: []].append(continuation)
                return false
            }
            if isHeld {
                continuation.resume()
            }
        }
    }

    /// Answers the oldest held request of `key` whose consumer is still there with `behavior` and
    /// takes it off the queue. With every held request already cancelled, the oldest one is taken
    /// off instead and nothing is delivered. Releasing a key with nothing held is a mistake in
    /// the test and is recorded as an issue.
    static func release(_ key: Key, with behavior: Behavior, sourceLocation: SourceLocation = #_sourceLocation) {
        let isReleased = state.withLock { state in
            guard var queue = state.held[key], !queue.isEmpty else {
                return false
            }
            let index = queue.firstIndex { !$0.isCancelled } ?? queue.startIndex
            let oldest = queue.remove(at: index)
            state.held[key] = queue
            if !oldest.isCancelled {
                schedule(oldest, answering: behavior)
            }
            return true
        }
        if !isReleased {
            Issue.record("CatalogMockScenario: release(\(key)) with no request held", sourceLocation: sourceLocation)
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
