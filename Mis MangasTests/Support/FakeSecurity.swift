//
//  FakeSecurity.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Synchronization

/// Scripted `SecurityData` for the layers above authentication (collection repository,
/// ViewModels), whose tests need to decide what the session does rather than exercise it. Every
/// requirement is replaced: nothing reaches the network or a store.
///
/// The fake keeps a tiny session model so sequences read naturally: a successful `login` or
/// `register` stores `issuedToken` and the email, `refresh` replaces a stored token with
/// `issuedToken`, `clearToken` forgets the token and keeps the email, `logout` forgets both.
/// Each operation can be made to fail with a configured `AuthError`, and every call is counted.
///
/// Configure with `configure { $0.… = … }` and read the oracle with `calls(_:)` and `snapshot`.
/// Both are `nonisolated`, so tests on any actor use them without `await`.
final class FakeSecurity: SecurityData {
    enum Method: Hashable {
        case appToken
        case currentToken
        case storedEmail
        case register
        case login
        case refresh
        case validToken
        case me
        case clearToken
        case logout
        case validateJWT
    }

    struct Behavior {
        /// Token returned by `currentToken` and `validToken`; `nil` = signed out or expired.
        var token: String?
        /// Email returned by `storedEmail`; survives `clearToken`.
        var email: String?
        /// Token stored by a successful `login`, `register` or `refresh`.
        var issuedToken = "fake.issued.token"
        var appToken = "fake-app-token"
        var registerError: AuthError?
        var loginError: AuthError?
        var refreshError: AuthError?
        /// Thrown by `validToken` before looking at `token`.
        var validTokenError: AuthError?
        var meResult: Result<UserResponse, AuthError> = .failure(.sessionExpired)
        var clearTokenError: AuthError?
        var logoutError: AuthError?
        var validateJWTResult: Result<JWTPayload, AuthError> = .failure(.invalidToken)
    }

    private struct State {
        var behavior: Behavior
        var calls: [Method: Int] = [:]
    }

    let store: any SecureStore
    let session: URLSession
    private let state: Mutex<State>

    nonisolated init(token: String? = nil, email: String? = nil) {
        store = InMemorySecureStore()
        session = URLSessionMockInterface.makeSession()
        state = Mutex(State(behavior: Behavior(token: token, email: email)))
    }

    // MARK: - Test controls

    nonisolated func configure(_ change: (inout Behavior) -> Void) {
        state.withLock { change(&$0.behavior) }
    }

    /// How many times `method` was called.
    nonisolated func calls(_ method: Method) -> Int {
        state.withLock { $0.calls[method] ?? 0 }
    }

    /// The current scripted state (token and email after the calls so far).
    nonisolated var snapshot: Behavior {
        state.withLock { $0.behavior }
    }

    /// Counts the call and applies `body` to the behavior under the lock.
    private nonisolated func record<Output: Sendable>(_ method: Method, _ body: (inout Behavior) -> Output) -> Output {
        state.withLock { state -> Output in
            state.calls[method, default: 0] += 1
            return body(&state.behavior)
        }
    }

    // MARK: - SecurityData

    func appToken() throws(AuthError) -> String {
        record(.appToken) { $0.appToken }
    }

    func currentToken() throws(AuthError) -> String? {
        record(.currentToken) { $0.token }
    }

    func storedEmail() throws(AuthError) -> String? {
        record(.storedEmail) { $0.email }
    }

    func register(email: String, password: String) async throws(AuthError) {
        try record(.register) { behavior -> Result<Void, AuthError> in
            if let error = behavior.registerError {
                return .failure(error)
            }
            behavior.token = behavior.issuedToken
            behavior.email = email
            return .success(())
        }.get()
    }

    func login(email: String, password: String) async throws(AuthError) {
        try record(.login) { behavior -> Result<Void, AuthError> in
            if let error = behavior.loginError {
                return .failure(error)
            }
            behavior.token = behavior.issuedToken
            behavior.email = email
            return .success(())
        }.get()
    }

    func refresh() async throws(AuthError) {
        try record(.refresh) { behavior -> Result<Void, AuthError> in
            if let error = behavior.refreshError {
                return .failure(error)
            }
            guard behavior.token != nil else {
                return .failure(.sessionExpired)
            }
            behavior.token = behavior.issuedToken
            return .success(())
        }.get()
    }

    func validToken() async throws(AuthError) -> String {
        try record(.validToken) { behavior -> Result<String, AuthError> in
            if let error = behavior.validTokenError {
                return .failure(error)
            }
            guard let token = behavior.token else {
                return .failure(.sessionExpired)
            }
            return .success(token)
        }.get()
    }

    func me() async throws(AuthError) -> UserResponse {
        try record(.me) { $0.meResult }.get()
    }

    func clearToken() throws(AuthError) {
        try record(.clearToken) { behavior -> Result<Void, AuthError> in
            if let error = behavior.clearTokenError {
                return .failure(error)
            }
            behavior.token = nil
            return .success(())
        }.get()
    }

    func logout() throws(AuthError) {
        try record(.logout) { behavior -> Result<Void, AuthError> in
            if let error = behavior.logoutError {
                return .failure(error)
            }
            behavior.token = nil
            behavior.email = nil
            return .success(())
        }.get()
    }

    func validateJWT(_ token: String) throws(AuthError) -> JWTPayload {
        try record(.validateJWT) { $0.validateJWTResult }.get()
    }
}
