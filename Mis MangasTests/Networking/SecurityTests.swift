//
//  SecurityTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

extension SharedMockSuites {
    /// The session operations of `extension SecurityData` through the real pipeline (endpoint →
    /// request → transport → status mapping → decode → store), with the transport replaced by
    /// `URLSessionMockInterface` and the Keychain by `InMemorySecureStore`.
    ///
    /// Oracles, never the code under test: the requests captured by the mock (headers, body, hit
    /// counts) checked against the contract verified on the live API, the dictionary of the
    /// in-memory store read directly, and the claims of the synthetic tokens. Store keys: `"jwt"`
    /// holds the token, `"userEmail"` the signed-in email.
    @Suite("Security")
    struct SecurityTests {
        private static let email = SessionTestTokenFactory.email
        private static let password = "example-password-8"
        /// base64("reader@example.com:example-password-8"), computed outside the app.
        private static let basicCredentials = "cmVhZGVyQGV4YW1wbGUuY29tOmV4YW1wbGUtcGFzc3dvcmQtOA=="
        private static let appToken = "test-app-token"
        /// `errSecInteractionNotAllowed`: what Keychain Services returns while the device is locked.
        private static let keychainFailure: OSStatus = -25308
        /// `id` of `users_me.json`.
        private static let meUserID = UUID(uuidString: "B093C17B-0AF9-453C-81F9-D57B86197A11")

        private let store: InMemorySecureStore
        private let security: SecurityTestConformer

        init() {
            SessionMockScenario.reset()
            let store = InMemorySecureStore()
            self.store = store
            security = SecurityTestConformer(store: store, appToken: Self.appToken)
        }

        /// A signed-in session: `token` under `"jwt"` and the email under `"userEmail"`.
        private func seedSession(token: String) {
            store.seed(token, key: "jwt")
            store.seed(Self.email, key: "userEmail")
        }

        // MARK: - register

        @Test(arguments: [201, 200])
        func `register posts the credentials with App-Token and accepts any 2xx`(status: Int) async throws {
            SessionMockScenario.set(.createUser, .status(status))

            try await security.register(email: Self.email, password: Self.password)

            #expect(SessionMockScenario.hits(.createUser) == 1)
            #expect(SessionMockScenario.totalHits() == 1)
            let sent = try #require(SessionMockScenario.lastRequest(.createUser))
            #expect(sent.method == "POST")
            #expect(sent.header("App-Token") == Self.appToken)
            #expect(sent.header("Authorization") == nil)
            #expect(sent.header("Content-Type") == "application/json; charset=utf-8")
            #expect(try sent.decodedBody(as: [String: String].self) == ["email": Self.email, "password": Self.password])
        }

        @Test func `register maps 400 User already exists to emailAlreadyRegistered`() async {
            SessionMockScenario.respondWithError(.createUser, status: 400, reason: "User already exists")

            await expectAuthError(.emailAlreadyRegistered) {
                try await security.register(email: Self.email, password: Self.password)
            }

            #expect(SessionMockScenario.hits(.createUser) == 1)
            #expect(store.storedKeys.isEmpty)
        }

        @Test(arguments: [
            "password is less than minimum of 8 character(s)",
            "email is not a valid email address",
        ])
        func `register maps any other 400 to server`(reason: String) async {
            SessionMockScenario.respondWithError(.createUser, status: 400, reason: reason)

            await expectAuthError(.server(.http(status: 400))) {
                try await security.register(email: Self.email, password: Self.password)
            }

            #expect(store.storedKeys.isEmpty)
        }

        @Test func `register maps a rejected App-Token (401) to server, never to invalidCredentials`() async {
            SessionMockScenario.respondWithError(.createUser, status: 401, reason: "Unauthorized")

            await expectAuthError(.server(.unauthorized)) {
                try await security.register(email: Self.email, password: Self.password)
            }

            #expect(store.storedKeys.isEmpty)
        }

        @Test func `register without connection throws offline`() async {
            SessionMockScenario.set(.createUser, .transportError(.notConnectedToInternet))

            await expectAuthError(.offline) {
                try await security.register(email: Self.email, password: Self.password)
            }

            #expect(store.storedKeys.isEmpty)
        }

        // MARK: - login

        @Test func `login sends Basic credentials to POST users jwt login and stores the token and the email`() async throws {
            let token = SessionTestTokenFactory.fresh()
            SessionMockScenario.respondWithToken(.jwtLogin, token)

            try await security.login(email: Self.email, password: Self.password)

            let sent = try #require(SessionMockScenario.lastRequest(.jwtLogin))
            #expect(sent.method == "POST")
            #expect(sent.header("Authorization") == "Basic \(Self.basicCredentials)")
            #expect(sent.header("App-Token") == nil)
            #expect(SessionMockScenario.totalHits() == 1)
            #expect(store.storedString("jwt") == token)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `login rejected with 401 throws invalidCredentials and stores nothing`() async {
            SessionMockScenario.respondWithError(.jwtLogin, status: 401, reason: "Unauthorized")

            await expectAuthError(.invalidCredentials) {
                try await security.login(email: Self.email, password: Self.password)
            }

            #expect(SessionMockScenario.hits(.jwtLogin) == 1)
            #expect(store.storedKeys.isEmpty)
        }

        @Test func `login that receives an unreadable token throws invalidToken and stores nothing`() async {
            SessionMockScenario.respondWithToken(.jwtLogin, "not-a-jwt")

            await expectAuthError(.invalidToken) {
                try await security.login(email: Self.email, password: Self.password)
            }

            #expect(store.storedKeys.isEmpty)
        }

        @Test func `login that receives an expired token throws sessionExpired and stores nothing`() async {
            SessionMockScenario.respondWithToken(.jwtLogin, SessionTestTokenFactory.expired())

            await expectAuthError(.sessionExpired) {
                try await security.login(email: Self.email, password: Self.password)
            }

            #expect(store.storedKeys.isEmpty)
        }

        @Test func `login without connection throws offline and stores nothing`() async {
            SessionMockScenario.set(.jwtLogin, .transportError(.notConnectedToInternet))

            await expectAuthError(.offline) {
                try await security.login(email: Self.email, password: Self.password)
            }

            #expect(SessionMockScenario.hits(.jwtLogin) == 1)
            #expect(store.storedKeys.isEmpty)
        }

        @Test(arguments: ["jwt", "userEmail"])
        func `login whose keychain write fails throws keychain with that status and leaves no partial session`(failingKey: String) async {
            SessionMockScenario.respondWithToken(.jwtLogin, SessionTestTokenFactory.fresh())
            store.failNextWrite(with: Self.keychainFailure, key: failingKey)

            await expectAuthError(.keychain(Self.keychainFailure)) {
                try await security.login(email: Self.email, password: Self.password)
            }

            #expect(store.storedKeys.isEmpty)
        }

        // MARK: - validateJWT

        @Test func `validateJWT returns the claims of a token that has not expired`() async throws {
            let exp = SessionTestTokenFactory.expSeconds(fromNow: 3600)

            let payload = try await security.validateJWT(SessionTestTokenFactory.makeJWT(exp: exp))

            #expect(payload.exp == Date(timeIntervalSince1970: exp))
            #expect(payload.email == Self.email)
            #expect(payload.userID == SessionTestTokenFactory.userID)
        }

        @Test func `validateJWT rejects an expired token with sessionExpired`() async {
            await expectAuthError(.sessionExpired) {
                try await security.validateJWT(SessionTestTokenFactory.expired())
            }
        }

        @Test func `validateJWT rejects an unreadable token with invalidToken`() async {
            await expectAuthError(.invalidToken) {
                try await security.validateJWT("header.payload")
            }
        }

        // MARK: - validToken

        @Test(arguments: [24 * 3600.0, 23 * 3600.0 + 300])
        func `validToken returns a stored token with at least 23 h left without touching the network`(secondsLeft: TimeInterval) async throws {
            let token = SessionTestTokenFactory.makeJWT(expiringIn: secondsLeft)
            seedSession(token: token)

            let result = try await security.validToken()

            #expect(result == token)
            #expect(SessionMockScenario.totalHits() == 0)
            #expect(store.storedString("jwt") == token)
        }

        @Test(arguments: [23 * 3600.0 - 300, 2 * 3600.0])
        func `validToken renews a stored token with less than 23 h left and returns the renewed one`(secondsLeft: TimeInterval) async throws {
            let old = SessionTestTokenFactory.makeJWT(expiringIn: secondsLeft)
            let renewed = SessionTestTokenFactory.fresh()
            seedSession(token: old)
            SessionMockScenario.respondWithToken(.jwtRefresh, renewed)

            let result = try await security.validToken()

            #expect(result == renewed)
            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(SessionMockScenario.totalHits() == 1)
            #expect(SessionMockScenario.lastRequest(.jwtRefresh)?.method == "POST")
            #expect(SessionMockScenario.authorization(.jwtRefresh) == "Bearer \(old)")
            #expect(store.storedString("jwt") == renewed)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `validToken with an expired token deletes it, keeps the email and throws sessionExpired without network`() async {
            seedSession(token: SessionTestTokenFactory.expired())

            await expectAuthError(.sessionExpired) {
                try await security.validToken()
            }

            #expect(SessionMockScenario.totalHits() == 0)
            #expect(store.storedString("jwt") == nil)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test(arguments: SessionTestTokenFactory.unreadable)
        func `validToken treats an unreadable stored token as expired`(reason: String, token: String) async {
            seedSession(token: token)

            await expectAuthError(.sessionExpired) {
                try await security.validToken()
            }

            #expect(SessionMockScenario.totalHits() == 0)
            #expect(store.storedString("jwt") == nil)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `validToken without a stored token throws sessionExpired without network`() async {
            store.seed(Self.email, key: "userEmail")

            await expectAuthError(.sessionExpired) {
                try await security.validToken()
            }

            #expect(SessionMockScenario.totalHits() == 0)
            #expect(store.storedKeys == ["userEmail"])
        }

        @Test func `validToken whose renewal is rejected with 401 deletes the token, keeps the email and throws sessionExpired`() async {
            seedSession(token: SessionTestTokenFactory.aging())
            SessionMockScenario.respondWithError(.jwtRefresh, status: 401, reason: "Unauthorized")

            await expectAuthError(.sessionExpired) {
                try await security.validToken()
            }

            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(store.storedString("jwt") == nil)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `validToken whose renewal fails without connection throws offline and keeps the session`() async {
            let old = SessionTestTokenFactory.aging()
            seedSession(token: old)
            SessionMockScenario.set(.jwtRefresh, .transportError(.notConnectedToInternet))

            await expectAuthError(.offline) {
                try await security.validToken()
            }

            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(store.storedString("jwt") == old)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `validToken whose renewal gets a 5xx throws server and keeps the session`() async {
            let old = SessionTestTokenFactory.aging()
            seedSession(token: old)
            SessionMockScenario.set(.jwtRefresh, .status(503))

            await expectAuthError(.server(.serverError)) {
                try await security.validToken()
            }

            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(store.storedString("jwt") == old)
            #expect(store.storedString("userEmail") == Self.email)
        }

        // MARK: - refresh

        @Test func `refresh sends the stored token as Bearer and stores the renewed one`() async throws {
            let old = SessionTestTokenFactory.makeJWT(expiringIn: 12 * 3600)
            let renewed = SessionTestTokenFactory.fresh()
            seedSession(token: old)
            SessionMockScenario.respondWithToken(.jwtRefresh, renewed)

            try await security.refresh()

            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(SessionMockScenario.authorization(.jwtRefresh) == "Bearer \(old)")
            #expect(store.storedString("jwt") == renewed)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `refresh rejected with 401 deletes the token, keeps the email and throws sessionExpired`() async {
            seedSession(token: SessionTestTokenFactory.fresh())
            SessionMockScenario.respondWithError(.jwtRefresh, status: 401, reason: "Unauthorized")

            await expectAuthError(.sessionExpired) {
                try await security.refresh()
            }

            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(store.storedString("jwt") == nil)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `refresh without connection throws offline and keeps the stored token`() async {
            let old = SessionTestTokenFactory.fresh()
            seedSession(token: old)
            SessionMockScenario.set(.jwtRefresh, .transportError(.notConnectedToInternet))

            await expectAuthError(.offline) {
                try await security.refresh()
            }

            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(store.storedString("jwt") == old)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `refresh with a 5xx throws server and keeps the stored token`() async {
            let old = SessionTestTokenFactory.fresh()
            seedSession(token: old)
            SessionMockScenario.set(.jwtRefresh, .status(503))

            await expectAuthError(.server(.serverError)) {
                try await security.refresh()
            }

            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(store.storedString("jwt") == old)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `refresh with an expired stored token deletes it and throws sessionExpired without network`() async {
            seedSession(token: SessionTestTokenFactory.expired())

            await expectAuthError(.sessionExpired) {
                try await security.refresh()
            }

            #expect(SessionMockScenario.totalHits() == 0)
            #expect(store.storedString("jwt") == nil)
            #expect(store.storedString("userEmail") == Self.email)
        }

        @Test func `refresh without a stored token throws sessionExpired without network`() async {
            await expectAuthError(.sessionExpired) {
                try await security.refresh()
            }

            #expect(SessionMockScenario.totalHits() == 0)
        }

        // MARK: - me

        @Test func `me sends the valid token as Bearer to GET users jwt me and decodes the account`() async throws {
            let token = SessionTestTokenFactory.fresh()
            seedSession(token: token)
            SessionMockScenario.set(.jwtMe, .fixture("users_me.json"))

            let user = try await security.me()

            let sent = try #require(SessionMockScenario.lastRequest(.jwtMe))
            #expect(sent.method == "GET")
            #expect(sent.header("Authorization") == "Bearer \(token)")
            #expect(SessionMockScenario.totalHits() == 1)
            #expect(user.id == Self.meUserID)
            #expect(user.email == "reader@example.com")
        }

        @Test func `me renews an aging token first and authenticates with the renewed one`() async throws {
            let renewed = SessionTestTokenFactory.fresh()
            seedSession(token: SessionTestTokenFactory.aging())
            SessionMockScenario.respondWithToken(.jwtRefresh, renewed)
            SessionMockScenario.set(.jwtMe, .fixture("users_me.json"))

            _ = try await security.me()

            #expect(SessionMockScenario.hits(.jwtRefresh) == 1)
            #expect(SessionMockScenario.authorization(.jwtMe) == "Bearer \(renewed)")
        }

        @Test func `me without connection throws offline and keeps the session`() async {
            let token = SessionTestTokenFactory.fresh()
            seedSession(token: token)
            SessionMockScenario.set(.jwtMe, .transportError(.notConnectedToInternet))

            await expectAuthError(.offline) {
                try await security.me()
            }

            #expect(SessionMockScenario.hits(.jwtMe) == 1)
            #expect(store.storedString("jwt") == token)
        }

        // MARK: - Stored session

        @Test func `currentToken and storedEmail read the stored session`() async throws {
            let token = SessionTestTokenFactory.fresh()
            seedSession(token: token)

            #expect(try await security.currentToken() == token)
            #expect(try await security.storedEmail() == Self.email)
        }

        @Test func `clearToken deletes the token and keeps the email`() async throws {
            seedSession(token: SessionTestTokenFactory.fresh())

            try await security.clearToken()

            #expect(store.storedKeys == ["userEmail"])
            #expect(store.storedString("userEmail") == Self.email)
            #expect(try await security.storedEmail() == Self.email)
        }

        @Test func `logout deletes the token and the email`() async throws {
            seedSession(token: SessionTestTokenFactory.fresh())

            try await security.logout()

            #expect(store.storedKeys.isEmpty)
        }
    }
}
