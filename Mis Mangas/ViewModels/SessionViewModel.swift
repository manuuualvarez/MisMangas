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
        /// The launch is still deciding whether an earlier session resumes; nothing is shown yet.
        case restoring
        case idle
        case guest
        case authenticating
        case authenticated(email: String)
        case failed(AuthError)

        /// Two failures are the same state when they show the same message: `AuthError` carries
        /// underlying errors that cannot be compared, and the message is what the screen shows.
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.restoring, .restoring), (.idle, .idle), (.guest, .guest), (.authenticating, .authenticating):
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

    private(set) var state: State = .restoring
    /// Shown on the welcome screen after the session ended on its own.
    private(set) var expiredMessage: String?
    /// The last sign-out did not happen: the unsent changes or the stored session could not be
    /// removed. The alert that says so clears it.
    var isSignOutFailurePresented = false
    /// The user chose to go on without an account and has not signed in since. A sign-in started
    /// from there keeps the app on screen while it waits and if it fails.
    private(set) var isGuestModeChosen = false

    /// Everything a sign-out discards: the pending changes of the account and the blocked ones,
    /// as `refreshPendingChanges()` last read them.
    private(set) var unsentChangesCount = 0

    /// Whether the welcome screen takes the place of the app: signed out, or signing in without
    /// having chosen guest mode.
    var isWelcomeRequired: Bool {
        switch state {
        case .restoring, .guest, .authenticated:
            false
        case .idle:
            true
        case .authenticating, .failed:
            !isGuestModeChosen
        }
    }

    /// The account of the signed-in session, lowercased; `nil` without one. The queued changes
    /// carry it, so no other account ever sends them.
    var account: String? {
        guard case .authenticated(let email) = state else {
            return nil
        }
        return email.lowercased()
    }

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
    /// Builds the sync service of a session, signed in or not, for the coordinator.
    private let makeSyncService: @MainActor (String?) -> MangaSyncService
    private var currentTask: Task<Void, Never>?
    /// The sign-out in flight, if the operation in flight is one.
    private var signOutTask: Task<Void, Never>?

    init(
        security: any SecurityData,
        syncCoordinator: SyncCoordinator,
        syncActor: MangaSyncActor,
        defaults: UserDefaults,
        makeSyncService: @escaping @MainActor (String?) -> MangaSyncService
    ) {
        self.security = security
        self.syncCoordinator = syncCoordinator
        self.syncActor = syncActor
        self.defaults = defaults
        self.makeSyncService = makeSyncService
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
        isGuestModeChosen = true
        expiredMessage = nil
        state = .guest
    }

    func signOut() async {
        await replaceCurrentTask(signsOut: true) { [weak self] in
            await self?.logout()
        }
    }

    /// Resumes the session of an earlier launch without asking for the password, renewing its
    /// token; without one, returns to the guest mode if that was the choice. Only the launch
    /// restores: once decided, a second call (another window) changes nothing and interrupts
    /// nothing.
    func restoreSession() async {
        guard state == .restoring else { return }
        await replaceCurrentTask { [weak self] in
            await self?.restore()
        }
    }

    /// Ends a session the server no longer accepts. The email stays stored for the next launch,
    /// and the queued changes keep their account: only that account sends them if it returns.
    func expire() async {
        // A confirmed sign-out already ends the session: replacing it would stop it before it
        // discards the unsent changes it promised to discard. Only a sign-out that failed, and
        // left the session open, still has it expire.
        if let signOutTask {
            await signOutTask.value
            guard isAuthenticated else { return }
        }
        await replaceCurrentTask { [weak self] in
            await self?.markExpired()
        }
    }

    /// Reads how many changes a sign-out would discard, for its warning. If the store cannot be
    /// read, the last count stays.
    func refreshPendingChanges() async {
        guard let counts = try? await syncActor.pendingOperationCounts(for: account) else { return }
        unsentChangesCount = counts.pending + counts.blocked
    }

    /// Forgets the error of a failed attempt, so the next form opens clean. A guest stays a guest.
    func clearFailure() {
        if case .failed = state {
            state = isGuestModeChosen ? .guest : .idle
        }
    }

    // MARK: - Operations

    /// Cancels the operation in flight, then runs `operation` as the new one and waits for it.
    private func replaceCurrentTask(
        signsOut: Bool = false,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) async {
        currentTask?.cancel()
        let task = Task { await operation() }
        currentTask = task
        signOutTask = signsOut ? task : nil
        await task.value
        if signOutTask == task {
            signOutTask = nil
        }
    }

    private func authenticate(email: String, password: String, createsAccount: Bool) async {
        guard !Task.isCancelled else { return }
        if createsAccount, let error = Self.formError(email: email, password: password) {
            state = .failed(error)
            return
        }
        state = .authenticating
        // The account whose collection the device holds, read before the sign-in stores the new one.
        // If the Keychain cannot tell, the first pass still drops that account's queue and its
        // snapshot replaces the collection.
        let lastAccount = try? await security.storedEmail()
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
        guard !Task.isCancelled else {
            // The answer came after the user moved on, and it stored its session anyway: it is
            // undone, so leaving a sign-in never leaves a token behind. If another sign-in replaced
            // this one, its session may go too, and its next request asks to sign in again; that
            // is safer than one account's collection travelling with another account's token.
            try? await security.logout()
            return
        }
        let newAccount = email.lowercased()
        if let lastAccount, lastAccount.lowercased() != newAccount {
            // Another account's collection is never shown to this one. If the store cannot be
            // written now, the first pass's snapshot replaces that collection anyway.
            try? await syncActor.handOverCollection(to: newAccount)
            guard !Task.isCancelled else {
                // Abandoned during the hand-over: no token is left behind, as above.
                try? await security.logout()
                return
            }
        }
        defaults.removeObject(forKey: Self.guestKey)
        isGuestModeChosen = false
        expiredMessage = nil
        state = .authenticated(email: email)
    }

    /// The sync coordinator moves to the device-only service first: the pass in flight stops, and
    /// any pass asked for from now on sends nothing. The unsent changes go next, as the sign-out
    /// warning said; if they cannot be discarded, the session stays open with its service back.
    private func logout() async {
        await syncCoordinator.replaceService(makeSyncService(nil))
        guard !Task.isCancelled else { return }
        do {
            try await syncActor.clearOutbox()
        } catch {
            // The operation that cancelled this one decides the coordinator's service.
            guard !Task.isCancelled else { return }
            await syncCoordinator.replaceService(makeSyncService(account))
            isSignOutFailurePresented = true
            return
        }
        guard !Task.isCancelled else { return }
        isSignOutFailurePresented = false
        unsentChangesCount = 0
        do {
            // The address stays as the device's last account: the next sign-in of another account
            // hands the collection over to it.
            try await security.clearToken()
        } catch {
            // The Keychain still holds the session, and the next launch would resume it: the
            // session stays open, with its service back, and the profile says so.
            guard !Task.isCancelled else { return }
            await syncCoordinator.replaceService(makeSyncService(account))
            isSignOutFailurePresented = true
            return
        }
        guard !Task.isCancelled else { return }
        defaults.removeObject(forKey: Self.guestKey)
        isGuestModeChosen = false
        expiredMessage = nil
        state = .idle
    }

    private func restore() async {
        guard !Task.isCancelled else { return }
        isGuestModeChosen = defaults.bool(forKey: Self.guestKey)
        let email: String
        do {
            guard try await security.currentToken() != nil else {
                guard !Task.isCancelled else { return }
                state = isGuestModeChosen ? .guest : .idle
                return
            }
            guard !isGuestModeChosen else {
                // Guest mode is only chosen once the last session has ended, so a token next to it
                // is one that could not be removed then; it must not resume that session.
                try? await security.clearToken()
                guard !Task.isCancelled else { return }
                state = .guest
                return
            }
            guard let storedEmail = try await security.storedEmail() else {
                // A token without its account cannot resume a session, and left in place it would
                // resume one on a later launch.
                try? await security.clearToken()
                guard !Task.isCancelled else { return }
                state = isGuestModeChosen ? .guest : .idle
                return
            }
            email = storedEmail
        } catch {
            // The Keychain cannot be read: no session can be resumed, and none may linger.
            try? await security.clearToken()
            guard !Task.isCancelled else { return }
            showExpired()
            return
        }
        guard !Task.isCancelled else { return }
        // The renewal keeps the launch state: authenticating belongs to the sign-in forms.
        do {
            try await security.refresh()
        } catch {
            guard !Task.isCancelled else { return }
            switch error {
            case .sessionExpired, .invalidCredentials:
                // The renewal already removed the token.
                showExpired()
                return
            case .invalidToken, .keychain:
                // The renewal failed without removing the stored token, which cannot be trusted
                // to resume the session any more.
                try? await security.clearToken()
                guard !Task.isCancelled else { return }
                showExpired()
                return
            case .offline, .server, .invalidEmail, .weakPassword, .emailAlreadyRegistered:
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
