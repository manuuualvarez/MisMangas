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
/// The fake keeps a tiny session model so sequences read naturally: a successful `login` stores
/// `issuedToken` and the email, `refresh` replaces a stored token with `issuedToken`, `clearToken`
/// forgets the token and keeps the email, `logout` forgets both. `register` only counts the call
/// and applies `registerError`: creating an account does not sign in, so it stores nothing.
/// Each operation can be made to fail with a configured `AuthError`, and every call is counted.
///
/// With `holdsRefresh`, `refresh` stays in flight until the test calls `releaseRefresh(throwing:)`,
/// so a test decides what happens while a session is being restored. `waitUntilRefreshHeld(orUntilFinished:)`
/// returns once one is held. Cancelling the caller ends a held refresh at once with
/// `AuthError.server(.cancelled)`, as a cancelled request does.
///
/// With `holdsLogin`, `login` stays in flight until `releaseLogin(throwing:)`, and
/// `waitUntilLoginHeld(orUntilFinished:)` returns once one is held. A held login ignores the
/// cancellation of its caller: it plays an answer that is already arriving, so the caller sees it
/// (the session stored) after being cancelled. One login is held at a time; turn `holdsLogin` off
/// once it is held so the next one answers at once.
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
        /// Token stored by a successful `login` or `refresh`.
        var issuedToken = "fake.issued.token"
        var appToken = "fake-app-token"
        var registerError: AuthError?
        var loginError: AuthError?
        var refreshError: AuthError?
        /// Thrown by `currentToken`, as a Keychain that cannot be read.
        var currentTokenError: AuthError?
        /// Thrown by `validToken` before looking at `token`.
        var validTokenError: AuthError?
        var meResult: Result<UserResponse, AuthError> = .failure(.sessionExpired)
        var clearTokenError: AuthError?
        var logoutError: AuthError?
        var validateJWTResult: Result<JWTPayload, AuthError> = .failure(.invalidToken)
        /// `refresh` waits for `releaseRefresh(throwing:)` instead of answering at once.
        var holdsRefresh = false
        /// `login` waits for `releaseLogin(throwing:)` instead of answering at once.
        var holdsLogin = false
    }

    private struct State {
        var behavior: Behavior
        var calls: [Method: Int] = [:]
        /// The `refresh` in flight while `holdsRefresh` is set.
        var heldRefresh: CheckedContinuation<Result<Void, AuthError>, Never>?
        /// The `login` in flight while `holdsLogin` is set; it resumes with the error to throw, or
        /// `nil` to answer as an unheld one.
        var heldLogin: CheckedContinuation<AuthError?, Never>?
        /// Tests suspended in `waitUntilRefreshHeld` or `waitUntilLoginHeld`, by the method they
        /// wait for.
        var waiters: [Method: CheckedContinuation<Void, Never>] = [:]
        /// Methods whose watched task finished before the wait suspended: that wait returns at once.
        var finishedWaits: Set<Method> = []
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

    /// Returns once a `refresh` is held, or as soon as `task` finishes, so a test whose code
    /// under test never renews fails instead of hanging. Returns whether a `refresh` is held.
    nonisolated func waitUntilRefreshHeld<Success: Sendable, Failure: Error>(orUntilFinished task: Task<Success, Failure>) async -> Bool {
        await waitUntilHeld(.refresh, orUntilFinished: task)
    }

    /// Returns once a `login` is held, or as soon as `task` finishes, so a test whose code under
    /// test never signs in fails instead of hanging. Returns whether a `login` is held.
    nonisolated func waitUntilLoginHeld<Success: Sendable, Failure: Error>(orUntilFinished task: Task<Success, Failure>) async -> Bool {
        await waitUntilHeld(.login, orUntilFinished: task)
    }

    /// Answers the held `refresh`: with `error`, or else as an unheld one would. Does nothing when
    /// none is held (its caller was cancelled and it already ended).
    nonisolated func releaseRefresh(throwing error: AuthError? = nil) {
        let released = state.withLock { state -> (CheckedContinuation<Result<Void, AuthError>, Never>, Result<Void, AuthError>)? in
            guard let held = state.heldRefresh else {
                return nil
            }
            state.heldRefresh = nil
            if let error {
                return (held, .failure(error))
            }
            return (held, Self.completeRefresh(&state.behavior))
        }
        if let released {
            released.0.resume(returning: released.1)
        }
    }

    /// Answers the held `login`: with `error`, or else as an unheld one would (applying
    /// `loginError`, or storing the session). Does nothing when none is held.
    nonisolated func releaseLogin(throwing error: AuthError? = nil) {
        let held = state.withLock { state -> CheckedContinuation<AuthError?, Never>? in
            let held = state.heldLogin
            state.heldLogin = nil
            return held
        }
        held?.resume(returning: error)
    }

    private nonisolated static func isHeld(_ method: Method, in state: State) -> Bool {
        switch method {
        case .refresh:
            state.heldRefresh != nil
        case .login:
            state.heldLogin != nil
        default:
            false
        }
    }

    private nonisolated func waitUntilHeld<Success: Sendable, Failure: Error>(
        _ method: Method,
        orUntilFinished task: Task<Success, Failure>
    ) async -> Bool {
        let watcher = Task {
            _ = await task.result
            self.stopWaiting(for: method)
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isReady = state.withLock { state -> Bool in
                if Self.isHeld(method, in: state) || state.finishedWaits.contains(method) {
                    return true
                }
                state.waiters[method] = continuation
                return false
            }
            if isReady {
                continuation.resume()
            }
        }
        watcher.cancel()
        return state.withLock { state in
            state.finishedWaits.remove(method)
            return Self.isHeld(method, in: state)
        }
    }

    private nonisolated func resumeWaiter(for method: Method) {
        let waiter = state.withLock { $0.waiters.removeValue(forKey: method) }
        waiter?.resume()
    }

    private nonisolated func stopWaiting(for method: Method) {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard let waiter = state.waiters.removeValue(forKey: method) else {
                state.finishedWaits.insert(method)
                return nil
            }
            return waiter
        }
        waiter?.resume()
    }

    /// Parks the calling `refresh` until `releaseRefresh(throwing:)` or its cancellation.
    private nonisolated func heldRefreshOutcome() async -> Result<Void, AuthError> {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, AuthError>, Never>) in
                // Checked under the lock the cancellation handler also takes: either the handler
                // finds the continuation parked, or this sees the task already cancelled.
                let isCancelled = state.withLock { state -> Bool in
                    if Task.isCancelled {
                        return true
                    }
                    state.heldRefresh = continuation
                    return false
                }
                if isCancelled {
                    continuation.resume(returning: .failure(.server(.cancelled)))
                } else {
                    resumeWaiter(for: .refresh)
                }
            }
        } onCancel: {
            let held = self.state.withLock { state -> CheckedContinuation<Result<Void, AuthError>, Never>? in
                let held = state.heldRefresh
                state.heldRefresh = nil
                return held
            }
            held?.resume(returning: .failure(.server(.cancelled)))
        }
    }

    /// Parks the calling `login` until `releaseLogin(throwing:)`, whatever happens to its caller.
    private nonisolated func heldLoginAnswer() async -> AuthError? {
        await withCheckedContinuation { (continuation: CheckedContinuation<AuthError?, Never>) in
            state.withLock { $0.heldLogin = continuation }
            resumeWaiter(for: .login)
        }
    }

    /// What an answered `login` does to the scripted session.
    private nonisolated static func completeLogin(_ behavior: inout Behavior, email: String) -> Result<Void, AuthError> {
        if let error = behavior.loginError {
            return .failure(error)
        }
        behavior.token = behavior.issuedToken
        behavior.email = email
        return .success(())
    }

    /// What an answered `refresh` does to the scripted session.
    private nonisolated static func completeRefresh(_ behavior: inout Behavior) -> Result<Void, AuthError> {
        if let error = behavior.refreshError {
            return .failure(error)
        }
        guard behavior.token != nil else {
            return .failure(.sessionExpired)
        }
        behavior.token = behavior.issuedToken
        return .success(())
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
        try record(.currentToken) { behavior -> Result<String?, AuthError> in
            if let error = behavior.currentTokenError {
                return .failure(error)
            }
            return .success(behavior.token)
        }.get()
    }

    func storedEmail() throws(AuthError) -> String? {
        record(.storedEmail) { $0.email }
    }

    func register(email: String, password: String) async throws(AuthError) {
        try record(.register) { behavior -> Result<Void, AuthError> in
            if let error = behavior.registerError {
                return .failure(error)
            }
            return .success(())
        }.get()
    }

    func login(email: String, password: String) async throws(AuthError) {
        let isHeld = record(.login) { $0.holdsLogin }
        if isHeld, let error = await heldLoginAnswer() {
            throw error
        }
        try state.withLock { Self.completeLogin(&$0.behavior, email: email) }.get()
    }

    func refresh() async throws(AuthError) {
        let isHeld = record(.refresh) { $0.holdsRefresh }
        if isHeld {
            try await heldRefreshOutcome().get()
        } else {
            try state.withLock { Self.completeRefresh(&$0.behavior) }.get()
        }
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
