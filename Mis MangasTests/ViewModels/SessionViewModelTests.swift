//
//  SessionViewModelTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// Sign-up, sign-in, guest mode and sign-out as the welcome screens drive them, over a
/// `FakeSecurity` that scripts what the account backend answers.
///
/// Oracles, never the code under test: the call counts of the fake (a rejected form never
/// reaches `register` or `login`; "signed in" means exactly one `login` succeeded, since
/// `register` alone does not sign in), the errors the fake was told to throw, the rules the
/// acceptance scenarios state (a valid email, at least 8 characters), the guest preference
/// read straight from an isolated `UserDefaults` suite, and the outbox seeded through the real
/// `MangaSyncActor` and read back with a fresh `ModelContext` over its in-memory container.
///
/// A class only for `deinit`, which removes that suite. The sync coordinator starts with the guest
/// service and no test here runs a pass, so nothing reaches the network.
@Suite("SessionViewModel")
@MainActor
final class SessionViewModelTests {
    private static let email = "test@example.com"
    /// Exactly the 8 characters the backend requires.
    private static let longEnough = "12345678"
    /// One character short of the minimum.
    private nonisolated static let oneShort = "1234567"
    /// `errSecInteractionNotAllowed`: what Keychain Services returns while the device is locked.
    private nonisolated static let keychainFailure: OSStatus = -25308
    private static let guestKey = "session.guest"
    /// A session stored by an earlier launch, under another account.
    private static let earlierSession = "example.previous.jwt"
    private static let earlierEmail = "previous@example.com"
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let t1 = Date(timeIntervalSinceReferenceDate: 800_000_100)
    private static let t2 = Date(timeIntervalSinceReferenceDate: 800_000_200)

    private let security: FakeSecurity
    private let defaults: UserDefaults
    private let suiteName: String
    private let syncActor: MangaSyncActor
    private let container: ModelContainer
    private let viewModel: SessionViewModel

    init() throws {
        let suiteName = "SessionViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let security = FakeSecurity()
        let made = try PersistenceTestSupport.makeActor()
        let actor = made.actor
        let repository = DefaultMangaRepositoryTest()
        let taxonomyCache = TaxonomyCacheActor(mangaRepository: repository)
        let guestService = MangaSyncService(syncActor: actor, mangaRepository: repository, taxonomyCache: taxonomyCache)
        self.suiteName = suiteName
        self.defaults = defaults
        self.security = security
        syncActor = made.actor
        container = made.container
        viewModel = SessionViewModel(
            security: security,
            syncCoordinator: SyncCoordinator(service: guestService),
            syncActor: actor,
            defaults: defaults,
            makeSyncService: { account in
                CollectionTestSupport.makeService(actor: actor, account: account, security: security)
            }
        )
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Records an issue unless the state is `failed` with an error matching `expected`.
    private func expectFailed(_ expected: AuthErrorCase, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case let .failed(error) = viewModel.state else {
            Issue.record("Expected failed(\(expected)), got \(viewModel.state)", sourceLocation: sourceLocation)
            return
        }
        #expect(expected.matches(error), "Expected failed(\(expected)), got failed(\(error))", sourceLocation: sourceLocation)
        #expect(!viewModel.isAuthenticated, sourceLocation: sourceLocation)
    }

    /// A session left by an earlier launch: a stored token and its account's email.
    private func storeEarlierSession() {
        security.configure {
            $0.token = Self.earlierSession
            $0.email = Self.earlierEmail
        }
    }

    /// Saves a collection entry for each id through the real actor under `account` (`nil`: a guest),
    /// which queues one upload per entry, then blocks the operation of `blockedID` by failing it as
    /// the drain does.
    private func queueOperations(_ ids: [Int], account: String? = nil, blocking blockedID: Int? = nil) async throws {
        try await CollectionTestSupport.storeMangas(ids, in: syncActor, now: Self.t0)
        for id in ids {
            try await syncActor.saveCollectionEntry(mangaID: id, volumesOwned: [id], readingVolume: nil, completeCollection: false, account: account, now: Self.t1)
        }
        if let blockedID {
            try await CollectionTestSupport.block(mangaID: blockedID, in: syncActor, container: container, now: Self.t2)
        }
    }

    // MARK: - signUp

    @Test func `signUp with valid data creates the account, then signs in and ends authenticated with that email`() async {
        await viewModel.signUp(email: Self.email, password: Self.longEnough)

        #expect(security.calls(.register) == 1)
        #expect(security.calls(.login) == 1)
        #expect(viewModel.state == .authenticated(email: Self.email))
        #expect(viewModel.isAuthenticated)
    }

    @Test(arguments: ["test@example", "", "reader.example.com", "reader@", "@example.com"])
    func `signUp with an invalid email fails with invalidEmail and never reaches the server`(email: String) async {
        await viewModel.signUp(email: email, password: Self.longEnough)

        expectFailed(.invalidEmail)
        #expect(security.calls(.register) == 0)
        #expect(security.calls(.login) == 0)
    }

    @Test(arguments: [SessionViewModelTests.oneShort, ""])
    func `signUp with a password under 8 characters fails with weakPassword and never reaches the server`(password: String) async {
        await viewModel.signUp(email: Self.email, password: password)

        expectFailed(.weakPassword)
        #expect(security.calls(.register) == 0)
        #expect(security.calls(.login) == 0)
    }

    @Test func `signUp with an email already registered fails with emailAlreadyRegistered and never signs in`() async {
        security.configure { $0.registerError = .emailAlreadyRegistered }

        await viewModel.signUp(email: Self.email, password: Self.longEnough)

        expectFailed(.emailAlreadyRegistered)
        #expect(security.calls(.register) == 1)
        #expect(security.calls(.login) == 0)
    }

    @Test func `signUp whose account is created but whose sign-in fails ends failed with that error, never authenticated`() async {
        security.configure { $0.loginError = .offline }

        await viewModel.signUp(email: Self.email, password: Self.longEnough)

        expectFailed(.offline)
        #expect(security.calls(.register) == 1)
        #expect(security.calls(.login) == 1)
    }

    // MARK: - signIn

    @Test func `signIn with accepted credentials ends authenticated with that email`() async {
        await viewModel.signIn(email: Self.email, password: Self.longEnough)

        #expect(security.calls(.login) == 1)
        #expect(security.calls(.register) == 0)
        #expect(viewModel.state == .authenticated(email: Self.email))
        #expect(viewModel.isAuthenticated)
    }

    @Test func `signIn rejected with 401 fails with invalidCredentials`() async {
        security.configure { $0.loginError = .invalidCredentials }

        await viewModel.signIn(email: Self.email, password: Self.longEnough)

        expectFailed(.invalidCredentials)
        #expect(security.calls(.login) == 1)
    }

    @Test func `signIn without connection fails with offline`() async {
        security.configure { $0.loginError = .offline }

        await viewModel.signIn(email: Self.email, password: Self.longEnough)

        expectFailed(.offline)
        #expect(security.calls(.login) == 1)
    }

    @Test func `signIn whose session cannot be stored in the Keychain fails with keychain and its status`() async {
        security.configure { $0.loginError = .keychain(Self.keychainFailure) }

        await viewModel.signIn(email: Self.email, password: Self.longEnough)

        expectFailed(.keychain(Self.keychainFailure))
        #expect(security.calls(.login) == 1)
    }

    @Test func `signIn while restoreSession is in flight cancels the restore, and the final state is the sign-in`() async throws {
        security.configure {
            $0.token = Self.earlierSession
            $0.email = Self.earlierEmail
            $0.holdsRefresh = true
        }
        let viewModel = viewModel

        let restoring = Task { await viewModel.restoreSession() }
        // The restore is renewing the stored token and waits for the answer.
        try #require(await security.waitUntilRefreshHeld(orUntilFinished: restoring))
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        // Had the restore survived the sign-in, this answer would end it in idle with the
        // expired-session message.
        security.releaseRefresh(throwing: .sessionExpired)
        await restoring.value

        #expect(security.calls(.login) == 1)
        #expect(viewModel.state == .authenticated(email: Self.email))
        #expect(viewModel.expiredMessage == nil)
    }

    @Test func `clearFailure after a failed sign-in returns to idle, and leaves any other state alone`() async {
        security.configure { $0.loginError = .invalidCredentials }
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        expectFailed(.invalidCredentials)

        viewModel.clearFailure()

        #expect(viewModel.state == .idle)

        viewModel.continueAsGuest()
        viewModel.clearFailure()

        #expect(viewModel.state == .guest)
    }

    // MARK: - Form rules

    @Test(arguments: ["", "reader@example.com"])
    func `emailIssue stays silent while the field is empty or the address is valid`(email: String) {
        #expect(SessionViewModel.emailIssue(email) == nil)
    }

    @Test func `emailIssue reports invalidEmail for a typed address without a domain`() throws {
        let issue = try #require(SessionViewModel.emailIssue("test@example"))
        #expect(AuthErrorCase.invalidEmail.matches(issue))
    }

    @Test func `A sign-in can be sent with a valid address and any password, never with an empty one`() {
        #expect(SessionViewModel.canSubmitSignIn(email: Self.email, password: Self.oneShort))
        #expect(!SessionViewModel.canSubmitSignIn(email: Self.email, password: ""))
        #expect(!SessionViewModel.canSubmitSignIn(email: "test@example", password: Self.longEnough))
    }

    @Test func `confirmationIssue appears only once something different is typed in the confirmation`() {
        #expect(SessionViewModel.confirmationIssue(password: Self.longEnough, confirmation: "") == nil)
        #expect(SessionViewModel.confirmationIssue(password: Self.longEnough, confirmation: Self.longEnough) == nil)
        #expect(SessionViewModel.confirmationIssue(password: Self.longEnough, confirmation: Self.oneShort) == "Passwords don't match")
    }

    @Test func `A sign-up can be sent with a valid address and a confirmed password, even a short one the submit then refuses`() {
        #expect(SessionViewModel.canSubmitSignUp(email: Self.email, password: Self.oneShort, confirmation: Self.oneShort))
        #expect(!SessionViewModel.canSubmitSignUp(email: Self.email, password: Self.longEnough, confirmation: Self.oneShort))
        #expect(!SessionViewModel.canSubmitSignUp(email: Self.email, password: "", confirmation: ""))
        #expect(!SessionViewModel.canSubmitSignUp(email: "test@example", password: Self.longEnough, confirmation: Self.longEnough))
    }

    @Test func `An already registered email is reported under the email field, not under the password`() async {
        security.configure { $0.registerError = .emailAlreadyRegistered }

        await viewModel.signUp(email: Self.email, password: Self.longEnough)

        #expect(viewModel.emailFailureMessage == AuthError.emailAlreadyRegistered.localizedDescription)
        #expect(viewModel.passwordFailureMessage == nil)
    }

    @Test func `A short password is reported under the password field, not under the email`() async {
        await viewModel.signUp(email: Self.email, password: Self.oneShort)

        #expect(viewModel.passwordFailureMessage == AuthError.weakPassword.localizedDescription)
        #expect(viewModel.emailFailureMessage == nil)
    }

    // MARK: - Guest and sign-out

    @Test func `continueAsGuest enters guest mode and remembers the choice`() {
        viewModel.continueAsGuest()

        #expect(viewModel.state == .guest)
        #expect(!viewModel.isAuthenticated)
        #expect(defaults.bool(forKey: Self.guestKey))
        #expect(security.calls(.register) == 0)
        #expect(security.calls(.login) == 0)
    }

    @Test func `signOut after signing in forgets the token, keeps the address as the device's last account and returns to idle`() async throws {
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))

        await viewModel.signOut()

        #expect(security.calls(.clearToken) == 1)
        #expect(security.calls(.logout) == 0)
        #expect(security.snapshot.token == nil)
        #expect(security.snapshot.email == Self.email)
        #expect(viewModel.state == .idle)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func `signOut whose token cannot be removed keeps the session open and reports it`() async throws {
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))
        security.configure { $0.clearTokenError = .keychain(Self.keychainFailure) }

        await viewModel.signOut()

        // The Keychain still holds the session: pretending it ended would resume it at next launch.
        #expect(viewModel.state == .authenticated(email: Self.email))
        #expect(viewModel.isSignOutFailurePresented)
    }

    // MARK: - restoreSession

    @Test func `A new session waits in restoring until the restore decides, instead of showing the welcome screen`() {
        #expect(viewModel.state == .restoring)
        #expect(!viewModel.isAuthenticated)
    }

    @Test func `restoreSession stays in restoring while the stored token is being renewed, never authenticating, then resumes the stored account`() async throws {
        storeEarlierSession()
        security.configure { $0.holdsRefresh = true }
        let viewModel = viewModel

        let restoring = Task { await viewModel.restoreSession() }
        try #require(await security.waitUntilRefreshHeld(orUntilFinished: restoring))

        // Authenticating is what a sign-in form shows; it would route the launch to the welcome screen.
        #expect(viewModel.state == .restoring)

        security.releaseRefresh()
        await restoring.value

        #expect(viewModel.state == .authenticated(email: Self.earlierEmail))
    }

    @Test func `restoreSession with a stored token renews it and resumes the stored account without asking for the password`() async {
        storeEarlierSession()

        await viewModel.restoreSession()

        #expect(security.calls(.refresh) == 1)
        #expect(security.calls(.login) == 0)
        #expect(viewModel.state == .authenticated(email: Self.earlierEmail))
        #expect(viewModel.expiredMessage == nil)
    }

    @Test(arguments: [AuthError.sessionExpired, .invalidToken, .invalidCredentials])
    func `restoreSession whose renewal is refused ends in idle with the expired-session message and keeps the stored email`(refusal: AuthError) async {
        storeEarlierSession()
        security.configure { $0.refreshError = refusal }

        await viewModel.restoreSession()

        #expect(security.calls(.refresh) == 1)
        #expect(viewModel.state == .idle)
        #expect(!viewModel.isAuthenticated)
        #expect(viewModel.expiredMessage == AuthError.sessionExpired.errorDescription)
        // An expiry is not a sign-out: the email stays, so the next sign-in can tell whether the
        // account changed.
        #expect(security.calls(.logout) == 0)
    }

    @Test(arguments: [AuthError.offline, .server(.serverError)])
    func `restoreSession whose renewal fails without connection or with a server error keeps the session`(failure: AuthError) async {
        storeEarlierSession()
        security.configure { $0.refreshError = failure }

        await viewModel.restoreSession()

        #expect(security.calls(.refresh) == 1)
        #expect(viewModel.state == .authenticated(email: Self.earlierEmail))
        #expect(viewModel.expiredMessage == nil)
        #expect(security.calls(.clearToken) == 0)
        #expect(security.calls(.logout) == 0)
    }

    @Test func `restoreSession without a stored token returns to guest mode when that was the choice`() async {
        defaults.set(true, forKey: Self.guestKey)

        await viewModel.restoreSession()

        #expect(viewModel.state == .guest)
        #expect(security.calls(.refresh) == 0)
    }

    @Test func `restoreSession without a stored token or a guest choice ends in idle, with no expired-session message`() async {
        await viewModel.restoreSession()

        #expect(viewModel.state == .idle)
        #expect(viewModel.expiredMessage == nil)
        #expect(security.calls(.refresh) == 0)
    }

    // MARK: - expire

    @Test func `expire after signing in forgets the token, keeps the email and returns to idle with the expired-session message`() async throws {
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))

        await viewModel.expire()

        #expect(viewModel.state == .idle)
        #expect(viewModel.expiredMessage == AuthError.sessionExpired.errorDescription)
        #expect(security.calls(.clearToken) == 1)
        #expect(security.calls(.logout) == 0)
        #expect(security.snapshot.email == Self.email)
    }

    // MARK: - Unsent changes

    @Test func `unsentChangesCount counts the pending and blocked changes of the signed-in account and the guest's, never another account's`() async throws {
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))
        try await queueOperations([1, 2], account: Self.email, blocking: 2)
        try await queueOperations([3], account: nil)
        try await queueOperations([4], account: Self.earlierEmail)

        await viewModel.refreshPendingChanges()

        #expect(viewModel.unsentChangesCount == 3)
    }

    @Test func `signOut discards every unsent change, blocked ones included, forgets the token and keeps the local collection`() async throws {
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))
        try await queueOperations([1, 2], blocking: 2)

        await viewModel.signOut()

        #expect(security.calls(.clearToken) == 1)
        #expect(viewModel.state == .idle)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.operations(in: context).isEmpty)
        #expect(try CollectionTestSupport.entries(in: context).map(\.mangaID) == [1, 2])
    }

    // MARK: - Account that owns each change

    @Test func `account is the signed-in address in lowercase, and nil before signing in, after the session expires and as a guest`() async throws {
        #expect(viewModel.account == nil)

        await viewModel.signIn(email: "Test@Example.COM", password: Self.longEnough)
        try #require(viewModel.isAuthenticated)

        #expect(viewModel.account == "test@example.com")

        await viewModel.expire()
        #expect(viewModel.account == nil)

        viewModel.continueAsGuest()
        #expect(viewModel.account == nil)
    }

    @Test func `account of a session resumed at launch is its stored address`() async {
        storeEarlierSession()

        await viewModel.restoreSession()

        #expect(viewModel.account == Self.earlierEmail)
    }

    @Test func `signIn on a device without a last account leaves another account's queue as it was, owned by that account`() async throws {
        try await queueOperations([1, 2], account: Self.earlierEmail)
        security.configure { $0.email = nil }

        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))

        let context = PersistenceTestSupport.freshContext(container)
        let operations = try CollectionTestSupport.operationsByManga(in: context)
        #expect(operations.map(\.mangaID) == [1, 2])
        #expect(operations.map(\.account) == [Self.earlierEmail, Self.earlierEmail])
    }

    // MARK: - A guest who signs in

    @Test(.timeLimit(.minutes(1)))
    func `A guest who signs in keeps the tabs while the sign-in waits, and leaves guest mode once it succeeds`() async throws {
        viewModel.continueAsGuest()
        security.configure { $0.holdsLogin = true }
        let viewModel = viewModel

        let signingIn = Task { await viewModel.signIn(email: Self.email, password: Self.longEnough) }
        try #require(await security.waitUntilLoginHeld(orUntilFinished: signingIn))

        #expect(viewModel.state == .authenticating)
        #expect(viewModel.isGuestModeChosen)
        // The welcome screen would replace the tabs and the profile form that is waiting.
        #expect(!viewModel.isWelcomeRequired)

        security.releaseLogin()
        await signingIn.value

        #expect(viewModel.state == .authenticated(email: Self.email))
        #expect(!viewModel.isGuestModeChosen)
        #expect(!viewModel.isWelcomeRequired)
    }

    @Test func `A guest whose sign-in is refused stays a guest, on the tabs, with the failure to show`() async {
        viewModel.continueAsGuest()
        security.configure { $0.loginError = .invalidCredentials }

        await viewModel.signIn(email: Self.email, password: Self.longEnough)

        expectFailed(.invalidCredentials)
        #expect(viewModel.isGuestModeChosen)
        #expect(!viewModel.isWelcomeRequired)
    }

    @Test func `A guest restored at launch whose sign-in is refused stays on the tabs`() async throws {
        defaults.set(true, forKey: Self.guestKey)
        await viewModel.restoreSession()
        try #require(viewModel.state == .guest)
        security.configure { $0.loginError = .invalidCredentials }

        await viewModel.signIn(email: Self.email, password: Self.longEnough)

        expectFailed(.invalidCredentials)
        #expect(viewModel.isGuestModeChosen)
        #expect(!viewModel.isWelcomeRequired)
    }

    @Test func `Without the guest choice the welcome screen waits for the restore, then shows in idle and after a refused sign-in`() async throws {
        #expect(!viewModel.isWelcomeRequired)

        await viewModel.restoreSession()
        try #require(viewModel.state == .idle)

        #expect(viewModel.isWelcomeRequired)

        security.configure { $0.loginError = .invalidCredentials }
        await viewModel.signIn(email: Self.email, password: Self.longEnough)

        expectFailed(.invalidCredentials)
        #expect(!viewModel.isGuestModeChosen)
        #expect(viewModel.isWelcomeRequired)
    }

    // MARK: - A sign-in answered after it was abandoned

    @Test(.timeLimit(.minutes(1)))
    func `A sign-in abandoned for guest mode whose answer arrives afterwards is logged out, and guest mode stays`() async throws {
        security.configure { $0.holdsLogin = true }
        let viewModel = viewModel

        let signingIn = Task { await viewModel.signIn(email: Self.email, password: Self.longEnough) }
        try #require(await security.waitUntilLoginHeld(orUntilFinished: signingIn))
        viewModel.continueAsGuest()
        // The server accepted the credentials: the fake stores the session, as the Keychain would.
        security.releaseLogin()
        await signingIn.value

        #expect(viewModel.state == .guest)
        #expect(viewModel.isGuestModeChosen)
        #expect(security.calls(.logout) == 1)
        #expect(security.snapshot.token == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A sign-in replaced by another sign-in is logged out when its answer arrives afterwards, so two accounts never mix`() async throws {
        security.configure { $0.holdsLogin = true }
        let viewModel = viewModel

        let first = Task { await viewModel.signIn(email: Self.earlierEmail, password: Self.longEnough) }
        try #require(await security.waitUntilLoginHeld(orUntilFinished: first))
        security.configure { $0.holdsLogin = false }
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))
        security.releaseLogin()
        await first.value

        // The late answer stored the first account over the second one. Undoing it costs the second
        // sign-in its token, which the next request turns into an expired session; keeping it would
        // send the second account's collection with the first account's token.
        #expect(security.calls(.logout) == 1)
        #expect(security.snapshot.token == nil)
        #expect(security.snapshot.email == nil)
    }

    // MARK: - restoreSession on an unusable session

    @Test(arguments: [AuthError.invalidToken, .keychain(SessionViewModelTests.keychainFailure)])
    func `restoreSession whose renewal fails with an unusable token forgets it and ends in idle with the expired-session message`(failure: AuthError) async {
        storeEarlierSession()
        security.configure { $0.refreshError = failure }

        await viewModel.restoreSession()

        #expect(viewModel.state == .idle)
        #expect(!viewModel.isAuthenticated)
        #expect(viewModel.expiredMessage == AuthError.sessionExpired.errorDescription)
        #expect(security.calls(.clearToken) == 1)
        #expect(security.snapshot.token == nil)
        #expect(security.calls(.logout) == 0)
    }

    @Test func `restoreSession that cannot read the Keychain tries to forget the token and ends in idle with the expired-session message`() async {
        storeEarlierSession()
        security.configure {
            $0.currentTokenError = .keychain(Self.keychainFailure)
            // The same locked Keychain refuses the removal too; the launch still ends.
            $0.clearTokenError = .keychain(Self.keychainFailure)
        }

        await viewModel.restoreSession()

        #expect(viewModel.state == .idle)
        #expect(viewModel.expiredMessage == AuthError.sessionExpired.errorDescription)
        #expect(security.calls(.clearToken) == 1)
        #expect(security.calls(.refresh) == 0)
    }

    @Test(arguments: [false, true])
    func `restoreSession with a stored token but no email forgets the token without renewing it, and follows the guest choice`(isGuestChosen: Bool) async {
        security.configure { $0.token = Self.earlierSession }
        let expected: SessionViewModel.State = isGuestChosen ? .guest : .idle
        if isGuestChosen {
            defaults.set(true, forKey: Self.guestKey)
        }

        await viewModel.restoreSession()

        #expect(security.calls(.clearToken) == 1)
        #expect(security.snapshot.token == nil)
        #expect(security.calls(.refresh) == 0)
        #expect(viewModel.state == expected)
    }

    @Test func `restoreSession with a stored session but the guest choice forgets the session and stays a guest`() async {
        // Guest mode is only chosen after the last session ended, so a token next to it is one that
        // could not be removed then.
        storeEarlierSession()
        defaults.set(true, forKey: Self.guestKey)

        await viewModel.restoreSession()

        #expect(viewModel.state == .guest)
        #expect(security.calls(.refresh) == 0)
        #expect(security.snapshot.token == nil)
    }

    // MARK: - restoreSession runs once

    @Test func `A second restoreSession after the launch resumed guest mode reads nothing and keeps guest mode`() async throws {
        defaults.set(true, forKey: Self.guestKey)
        await viewModel.restoreSession()
        try #require(viewModel.state == .guest)
        let reads = security.calls(.currentToken)

        await viewModel.restoreSession()

        #expect(security.calls(.currentToken) == reads)
        #expect(viewModel.state == .guest)
    }

    @Test func `A second restoreSession after the launch resumed the stored account neither reads nor renews again`() async throws {
        storeEarlierSession()
        await viewModel.restoreSession()
        try #require(viewModel.state == .authenticated(email: Self.earlierEmail))
        let reads = security.calls(.currentToken)

        await viewModel.restoreSession()

        #expect(security.calls(.currentToken) == reads)
        #expect(security.calls(.refresh) == 1)
        #expect(viewModel.state == .authenticated(email: Self.earlierEmail))
    }

    @Test(.timeLimit(.minutes(1)))
    func `restoreSession called while a sign-in waits leaves the sign-in running, and it ends authenticated`() async throws {
        await viewModel.restoreSession()
        try #require(viewModel.state == .idle)
        let reads = security.calls(.currentToken)
        security.configure { $0.holdsLogin = true }
        let viewModel = viewModel

        let signingIn = Task { await viewModel.signIn(email: Self.email, password: Self.longEnough) }
        try #require(await security.waitUntilLoginHeld(orUntilFinished: signingIn))
        // Another window of the app starting up.
        await viewModel.restoreSession()
        security.releaseLogin()
        await signingIn.value

        #expect(security.calls(.currentToken) == reads)
        #expect(security.calls(.login) == 1)
        #expect(viewModel.state == .authenticated(email: Self.email))
    }

    // MARK: - The collection of the device's last account

    /// Stores the collection a signed-out account left: manga 3 synced (no queued change), manga 1
    /// with a change of that account still queued, and manga 2 saved afterwards as a guest.
    private func storeCollectionLeftBy(_ account: String) async throws {
        try await CollectionTestSupport.storeMangas([1, 2, 3], in: syncActor, now: Self.t0)
        try await syncActor.saveCollectionEntry(mangaID: 3, volumesOwned: [3], readingVolume: nil, completeCollection: false, account: account, now: Self.t1)
        try await syncActor.clearOutbox()
        try await syncActor.saveCollectionEntry(mangaID: 1, volumesOwned: [1], readingVolume: nil, completeCollection: false, account: account, now: Self.t1)
        try await syncActor.saveCollectionEntry(mangaID: 2, volumesOwned: [2], readingVolume: nil, completeCollection: false, account: nil, now: Self.t2)
        security.configure { $0.email = account }
    }

    @Test func `signIn as an account other than the device's last one forgets that account's collection at once and keeps the guest's changes`() async throws {
        try await storeCollectionLeftBy(Self.earlierEmail)

        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.entries(in: context).map(\.mangaID) == [2])
        let operations = try CollectionTestSupport.operationsByManga(in: context)
        #expect(operations.map(\.mangaID) == [2])
        #expect(operations.map(\.account) == [nil])
        let mangas = try context.fetch(FetchDescriptor<Manga>(sortBy: [SortDescriptor(\.id)]))
        #expect(mangas.map(\.inCollection) == [false, true, false])
    }

    @Test func `signIn as the device's last account, whatever the case of the address, keeps its collection`() async throws {
        try await storeCollectionLeftBy(Self.email)

        await viewModel.signIn(email: Self.email.uppercased(), password: Self.longEnough)
        try #require(viewModel.isAuthenticated)

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.entries(in: context).map(\.mangaID) == [1, 2, 3])
        #expect(try CollectionTestSupport.operationsByManga(in: context).map(\.mangaID) == [1, 2])
    }

    @Test func `signIn on a device without a last account keeps the local collection`() async throws {
        try await storeCollectionLeftBy(Self.earlierEmail)
        security.configure { $0.email = nil }

        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.isAuthenticated)

        let context = PersistenceTestSupport.freshContext(container)
        #expect(try CollectionTestSupport.entries(in: context).map(\.mangaID) == [1, 2, 3])
    }
}
