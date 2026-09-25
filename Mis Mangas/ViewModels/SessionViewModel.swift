//
//  SessionViewModel.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
import Observation

/// The account session the whole app follows: signed out, guest or signed in. It validates the
/// forms before touching the network, drives `SecurityData` and remembers the guest choice. The
/// token itself never reaches this type; it lives in the Keychain behind `security`.
///
/// Every operation replaces the one in flight: the previous task is cancelled before the new one
/// mutates the state, and a cancelled task never writes the state afterwards.
@Observable
@MainActor
final class SessionViewModel {
    enum State: Equatable {
        case idle
        case guest
        case authenticating
        case authenticated(email: String)
        case failed(AuthError)

        /// Two failures are the same state when they show the same message: `AuthError` carries
        /// underlying errors that cannot be compared, and the message is what the screen shows.
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.guest, .guest), (.authenticating, .authenticating):
                true
            case let (.authenticated(lhsEmail), .authenticated(rhsEmail)):
                lhsEmail == rhsEmail
            case let (.failed(lhsError), .failed(rhsError)):
                lhsError.localizedDescription == rhsError.localizedDescription
            default:
                false
            }
        }
    }

    /// `UserDefaults` key of the guest choice; not sensitive.
    static let guestKey = "session.guest"

    private(set) var state: State = .idle
    /// Shown on the welcome screen after the session ended on its own.
    private(set) var expiredMessage: String?

    var isAuthenticated: Bool {
        if case .authenticated = state {
            true
        } else {
            false
        }
    }

    /// A sign-in or sign-up is waiting for the server.
    var isAuthenticating: Bool {
        state == .authenticating
    }

    /// The message of the last failed attempt, for the form that made it.
    var failureMessage: String? {
        failure?.localizedDescription
    }

    /// The failure that concerns the address (invalid or already registered), for the email
    /// field of the sign-up form.
    var emailFailureMessage: String? {
        guard let failure, Self.concernsEmail(failure) else { return nil }
        return failure.localizedDescription
    }

    /// Any other failure, for the password fields of the sign-up form.
    var passwordFailureMessage: String? {
        guard let failure, !Self.concernsEmail(failure) else { return nil }
        return failure.localizedDescription
    }

    private var failure: AuthError? {
        if case let .failed(error) = state {
            error
        } else {
            nil
        }
    }

    private static func concernsEmail(_ error: AuthError) -> Bool {
        switch error {
        case .invalidEmail, .emailAlreadyRegistered:
            true
        case .weakPassword, .invalidCredentials, .sessionExpired, .invalidToken, .keychain, .offline, .server:
            false
        }
    }

    private let security: any SecurityData
    private let syncCoordinator: SyncCoordinator
    private let syncActor: MangaSyncActor
    private let defaults: UserDefaults
    private var currentTask: Task<Void, Never>?

    init(security: any SecurityData, syncCoordinator: SyncCoordinator, syncActor: MangaSyncActor, defaults: UserDefaults) {
        self.security = security
        self.syncCoordinator = syncCoordinator
        self.syncActor = syncActor
        self.defaults = defaults
    }

    func signIn(email: String, password: String) async {
        await replaceCurrentTask { [weak self] in
            await self?.authenticate(email: email, password: password, createsAccount: false)
        }
    }

    /// Creates the account, then signs in with it: the backend's registration does not open a
    /// session.
    func signUp(email: String, password: String) async {
        await replaceCurrentTask { [weak self] in
            await self?.authenticate(email: email, password: password, createsAccount: true)
        }
    }

    func continueAsGuest() {
        currentTask?.cancel()
        currentTask = nil
        defaults.set(true, forKey: Self.guestKey)
        expiredMessage = nil
        state = .guest
    }

    func signOut() async {
        await replaceCurrentTask { [weak self] in
            await self?.logout()
        }
    }

    /// Resumes the session of an earlier launch without asking for the password, renewing its
    /// token; without one, returns to the guest mode if that was the choice.
    func restoreSession() async {
        await replaceCurrentTask { [weak self] in
            await self?.restore()
        }
    }

    /// Ends a session the server no longer accepts. The email stays stored, so the next sign-in
    /// can tell whether the account changed.
    func expire() async {
        await replaceCurrentTask { [weak self] in
            await self?.markExpired()
        }
    }

    /// Forgets the error of a failed attempt, so the next form opens clean.
    func clearFailure() {
        if case .failed = state {
            state = .idle
        }
    }

    // MARK: - Operations

    /// Cancels the operation in flight, then runs `operation` as the new one and waits for it.
    private func replaceCurrentTask(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        currentTask?.cancel()
        let task = Task { await operation() }
        currentTask = task
        await task.value
    }

    private func authenticate(email: String, password: String, createsAccount: Bool) async {
        guard !Task.isCancelled else { return }
        if createsAccount, let error = Self.formError(email: email, password: password) {
            state = .failed(error)
            return
        }
        state = .authenticating
        do {
            if createsAccount {
                try await security.register(email: email, password: password)
            }
            try await security.login(email: email, password: password)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error)
            return
        }
        guard !Task.isCancelled else { return }
        defaults.removeObject(forKey: Self.guestKey)
        expiredMessage = nil
        state = .authenticated(email: email)
    }

    /// The sync coordinator stops first: a pass in flight must not go on with the session that is
    /// being closed.
    private func logout() async {
        await syncCoordinator.stop()
        guard !Task.isCancelled else { return }
        do {
            try await security.logout()
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error)
            return
        }
        guard !Task.isCancelled else { return }
        defaults.removeObject(forKey: Self.guestKey)
        expiredMessage = nil
        state = .idle
    }

    private func restore() async {
        guard !Task.isCancelled else { return }
        let email: String
        do {
            guard try await security.currentToken() != nil, let storedEmail = try await security.storedEmail() else {
                guard !Task.isCancelled else { return }
                state = defaults.bool(forKey: Self.guestKey) ? .guest : .idle
                return
            }
            email = storedEmail
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error)
            return
        }
        guard !Task.isCancelled else { return }
        state = .authenticating
        do {
            try await security.refresh()
        } catch {
            guard !Task.isCancelled else { return }
            switch error {
            case .sessionExpired, .invalidToken, .invalidCredentials:
                // The renewal already removed the token.
                showExpired()
                return
            case .offline, .server, .keychain, .invalidEmail, .weakPassword, .emailAlreadyRegistered:
                // The stored token is still valid: without a renewal the session goes on, and the
                // next authenticated request renews it or ends it.
                break
            }
        }
        guard !Task.isCancelled else { return }
        state = .authenticated(email: email)
    }

    private func markExpired() async {
        // A token that cannot be removed is not used again either: the server already rejects
        // it, so the next request that presents it ends the session once more.
        try? await security.clearToken()
        guard !Task.isCancelled else { return }
        showExpired()
    }

    private func showExpired() {
        expiredMessage = AuthError.sessionExpired.errorDescription
        state = .idle
    }

    // MARK: - Validation

    /// An address with a name, an `@` and a domain with a dot.
    static func isValidEmail(_ email: String) -> Bool {
        email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    /// The address problem to show under the field: none while it is empty or valid.
    static func emailIssue(_ email: String) -> AuthError? {
        email.isEmpty || isValidEmail(email) ? nil : .invalidEmail
    }

    /// A sign-in needs a valid address and a password; the server judges the password.
    static func canSubmitSignIn(email: String, password: String) -> Bool {
        isValidEmail(email) && !password.isEmpty
    }

    /// The confirmation problem to show under the password fields: none until something
    /// different is typed in the confirmation.
    static func confirmationIssue(password: String, confirmation: String) -> String? {
        confirmation.isEmpty || confirmation == password ? nil : String(localized: "Passwords don't match")
    }

    /// A sign-up needs a valid address and a password typed twice. Its length is checked on
    /// submit, so the form can say why it was refused.
    static func canSubmitSignUp(email: String, password: String, confirmation: String) -> Bool {
        isValidEmail(email) && !password.isEmpty && confirmation == password
    }

    /// The first problem of a sign-up form, checked before any request: a valid address and a
    /// password of at least 8 characters.
    static func formError(email: String, password: String) -> AuthError? {
        if !isValidEmail(email) {
            return .invalidEmail
        }
        if password.count < 8 {
            return .weakPassword
        }
        return nil
    }
}
