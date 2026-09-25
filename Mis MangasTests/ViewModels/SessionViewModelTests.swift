//
//  SessionViewModelTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// Sign-up, sign-in, guest mode and sign-out as the welcome screens drive them, over a
/// `FakeSecurity` that scripts what the account backend answers.
///
/// Oracles, never the code under test: the call counts of the fake (a rejected form never
/// reaches `register` or `login`; "signed in" means exactly one `login` succeeded, since
/// `register` alone does not sign in), the errors the fake was told to throw, the rules the
/// acceptance scenarios state (a valid email, at least 8 characters) and the guest preference
/// read straight from an isolated `UserDefaults` suite.
///
/// A class only for `deinit`, which removes that suite. The collection coordinator runs the
/// guest service, so nothing here reaches the network.
@Suite("SessionViewModel")
@MainActor
final class SessionViewModelTests {
    private static let email = "test@example.com"
    /// Exactly the 8 characters the backend requires.
    private static let longEnough = "12345678"
    /// One character short of the minimum.
    private nonisolated static let oneShort = "1234567"
    /// `errSecInteractionNotAllowed`: what Keychain Services returns while the device is locked.
    private static let keychainFailure: OSStatus = -25308
    private static let guestKey = "session.guest"
    /// A session stored by an earlier launch, under another account.
    private static let earlierSession = "example.previous.jwt"
    private static let earlierEmail = "previous@example.com"

    private let security: FakeSecurity
    private let defaults: UserDefaults
    private let suiteName: String
    private let viewModel: SessionViewModel

    init() throws {
        let suiteName = "SessionViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let security = FakeSecurity()
        let made = try PersistenceTestSupport.makeActor()
        let repository = DefaultMangaRepositoryTest()
        let guestService = MangaSyncService(
            syncActor: made.actor,
            mangaRepository: repository,
            taxonomyCache: TaxonomyCacheActor(mangaRepository: repository)
        )
        self.suiteName = suiteName
        self.defaults = defaults
        self.security = security
        viewModel = SessionViewModel(
            security: security,
            syncCoordinator: SyncCoordinator(service: guestService),
            syncActor: made.actor,
            defaults: defaults
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

    @Test func `signOut after signing in logs out and returns to idle`() async throws {
        await viewModel.signIn(email: Self.email, password: Self.longEnough)
        try #require(viewModel.state == .authenticated(email: Self.email))

        await viewModel.signOut()

        #expect(security.calls(.logout) == 1)
        #expect(viewModel.state == .idle)
        #expect(!viewModel.isAuthenticated)
    }
}
