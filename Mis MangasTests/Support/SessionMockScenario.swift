//
//  SessionMockScenario.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

/// Session-flavoured façade over the `CatalogMockScenario` slot that `URLSessionMockInterface`
/// serves: `POST /users`, `POST /users/jwt/login`, `POST /users/jwt/refresh` and
/// `GET /users/jwt/me`.
///
/// Suites that use it are nested under `SharedMockSuites` like every other mock user. A test
/// calls `reset()`, configures the routes it expects with `set(_:_:)`, `respondWithToken(_:_:)`
/// or `respondWithError(_:status:reason:)`, runs production code and reads the oracle: hit
/// counters, the captured `App-Token` / `Authorization` headers and the body put on the wire.
/// An unconfigured route answers 599, so an unexpected call never succeeds by accident.
///
/// Token responses are always built from `SessionTestTokenFactory` tokens: no real token is
/// ever committed.
enum SessionMockScenario {
    typealias Key = CatalogMockScenario.Key
    typealias Behavior = CatalogMockScenario.Behavior
    typealias CapturedRequest = CatalogMockScenario.CapturedRequest

    // MARK: - Configuration

    static func reset() {
        CatalogMockScenario.reset()
    }

    static func set(_ key: Key, _ behavior: Behavior) {
        CatalogMockScenario.set(key, behavior)
    }

    /// `status` with the `JWTTokenDTO` body the backend sends from login and refresh.
    static func respondWithToken(_ key: Key, _ token: String, status: Int = 200) {
        set(key, .json(tokenBody(token), status: status))
    }

    /// `status` with the backend error body `{"error": true, "reason": …}`.
    static func respondWithError(_ key: Key, status: Int, reason: String) {
        set(key, .json(#"{"error":true,"reason":"\#(reason)"}"#, status: status))
    }

    /// The wire form of `JWTTokenDTO` (24 h, Bearer) wrapping `token`.
    static func tokenBody(_ token: String) -> String {
        #"{"token":"\#(token)","expiresIn":86400,"tokenType":"Bearer"}"#
    }

    // MARK: - Oracle

    static func hits(_ key: Key) -> Int {
        CatalogMockScenario.hits(key)
    }

    /// Requests that reached the mock on any route: 0 means production never touched the wire.
    static func totalHits() -> Int {
        CatalogMockScenario.totalHits()
    }

    static func requests(_ key: Key) -> [CapturedRequest] {
        CatalogMockScenario.requests(key)
    }

    static func lastRequest(_ key: Key) -> CapturedRequest? {
        CatalogMockScenario.lastRequest(key)
    }

    /// `Authorization` of the last request of `key` (`Basic …` / `Bearer …`).
    static func authorization(_ key: Key) -> String? {
        lastRequest(key)?.header("Authorization")
    }

    /// `App-Token` of the last request of `key`.
    static func appToken(_ key: Key) -> String? {
        lastRequest(key)?.header("App-Token")
    }
}
