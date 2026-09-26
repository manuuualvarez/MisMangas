//
//  SecurityData.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// Account and session operations over the `/users` family of the backend. One 24 h JWT is kept
/// in the store under `"jwt"` and the signed-in email under `"userEmail"`. Every operation is a
/// requirement with a default implementation in the extension, so test doubles replace any of
/// them through `any SecurityData`. `Sendable` is required: the existential of a protocol
/// isolated to a global actor is not `Sendable` by itself, and ViewModels on the main actor send
/// it to `@APIActor` on every call.
@APIActor
protocol SecurityData: NetworkInteractor, Sendable {
    var store: any SecureStore { get }

    /// Value of the `App-Token` header sent by `register`.
    func appToken() throws(AuthError) -> String
    func currentToken() throws(AuthError) -> String?
    func storedEmail() throws(AuthError) -> String?
    func register(email: String, password: String) async throws(AuthError)
    func login(email: String, password: String) async throws(AuthError)
    func refresh() async throws(AuthError)
    func validToken() async throws(AuthError) -> String
    func me() async throws(AuthError) -> UserResponse
    func clearToken() throws(AuthError)
    func logout() throws(AuthError)
    func validateJWT(_ token: String) throws(AuthError) -> JWTPayload
}

extension SecurityData {
    /// Remaining lifetime below which a stored token is renewed before use (23 h of a 24 h
    /// token): a session lasts while the app is used at least once a day, with at most one
    /// renewal per hour.
    static var renewalThreshold: TimeInterval { 23 * 3600 }

    func appToken() throws(AuthError) -> String {
        try AppToken.value()
    }

    func currentToken() throws(AuthError) -> String? {
        try readString(tokenKey)
    }

    func storedEmail() throws(AuthError) -> String? {
        try readString(emailKey)
    }

    /// Creates the account only; signing in afterwards is the caller's decision.
    func register(email: String, password: String) async throws(AuthError) {
        let request = try makeRequest(url: .createUser,
                                      method: .post,
                                      body: UsersCreate(email: email, password: password),
                                      authentication: .appToken,
                                      token: appToken())
        do {
            try await getStatus(request: request)
        } catch {
            if case .http(400, let body) = error, isUserAlreadyExists(body) {
                throw .emailAlreadyRegistered
            }
            throw networkFailure(error)
        }
    }

    /// Stores the token and the email together: if either write fails, nothing is left behind.
    func login(email: String, password: String) async throws(AuthError) {
        let credentials = Data("\(email):\(password)".utf8).base64EncodedString()
        let request = try makeRequest(url: .jwtLogin, method: .post, authentication: .basic, token: credentials)
        let response: JWTTokenDTO
        do {
            response = try await getJSON(request: request, type: JWTTokenDTO.self)
        } catch {
            if case .unauthorized = error {
                throw .invalidCredentials
            }
            throw networkFailure(error)
        }
        _ = try validateJWT(response.token)
        try store.write(Data(response.token.utf8), key: tokenKey)
        do {
            try store.write(Data(email.utf8), key: emailKey)
        } catch {
            try store.delete(tokenKey)
            throw error
        }
    }

    /// Exchanges the stored token for a new 24 h one. A stored token that is missing, expired,
    /// unreadable or rejected with 401 ends the session; a network or server failure keeps it. A
    /// token removed or replaced while the renewal waited also ends it, and nothing is stored.
    func refresh() async throws(AuthError) {
        let current = try usableStoredToken().token
        let request = try makeRequest(url: .jwtRefresh, method: .post, token: current)
        let response: JWTTokenDTO
        do {
            response = try await getJSON(request: request, type: JWTTokenDTO.self)
        } catch {
            if case .unauthorized = error {
                try clearToken()
                throw .sessionExpired
            }
            throw networkFailure(error)
        }
        _ = try validateJWT(response.token)
        // While the renewal waited, the session may have ended or another one begun: the answer
        // never brings back a token that is no longer the stored one.
        guard try currentToken() == current else {
            throw .sessionExpired
        }
        try store.write(Data(response.token.utf8), key: tokenKey)
    }

    /// The stored token, renewed first when less than `renewalThreshold` of its
    /// lifetime is left, so the session slides forward while the app is used.
    func validToken() async throws(AuthError) -> String {
        let (token, payload) = try usableStoredToken()
        guard payload.exp.timeIntervalSinceNow < Self.renewalThreshold else {
            return token
        }
        try await refresh()
        guard let renewed = try currentToken() else {
            throw .sessionExpired
        }
        return renewed
    }

    func me() async throws(AuthError) -> UserResponse {
        let token = try await validToken()
        let request = try makeRequest(url: .jwtMe, token: token)
        do {
            return try await getJSON(request: request, type: UserResponse.self)
        } catch {
            if case .unauthorized = error {
                try clearToken()
                throw .sessionExpired
            }
            throw networkFailure(error)
        }
    }

    /// Ends an expired session: the email stays so the next sign-in can detect a change of account.
    func clearToken() throws(AuthError) {
        try store.delete(tokenKey)
    }

    func logout() throws(AuthError) {
        try store.delete(tokenKey)
        try store.delete(emailKey)
    }

    func validateJWT(_ token: String) throws(AuthError) -> JWTPayload {
        let payload = try decodeJWTPayload(token)
        guard payload.exp > .now else {
            throw .sessionExpired
        }
        return payload
    }

    // MARK: - Helpers

    private var tokenKey: String { "jwt" }
    private var emailKey: String { "userEmail" }

    private func readString(_ key: String) throws(AuthError) -> String? {
        try store.read(key).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The stored token and its claims when it can still be used or renewed. Missing →
    /// `sessionExpired`; expired, unreadable or issued to another account than the stored email →
    /// deleted, then `sessionExpired`.
    private func usableStoredToken() throws(AuthError) -> (token: String, payload: JWTPayload) {
        guard let token = try currentToken() else {
            throw .sessionExpired
        }
        let payload: JWTPayload
        do {
            payload = try validateJWT(token)
        } catch {
            try clearToken()
            throw .sessionExpired
        }
        // A sign-in whose Keychain writes failed halfway can leave its token next to the previous
        // account's email: the token names its own account, and it never acts as another one.
        if let email = try storedEmail(), email.lowercased() != payload.email.lowercased() {
            try clearToken()
            throw .sessionExpired
        }
        return (token, payload)
    }

    private func makeRequest(url: URL,
                             method: HTTPMethod = .get,
                             body: (any Encodable)? = nil,
                             authentication: AuthenticationType = .bearer,
                             token: String) throws(AuthError) -> URLRequest {
        do {
            return try URLRequest.request(url: url, method: method, body: body, authentication: authentication, token: token)
        } catch {
            throw .server(error)
        }
    }

    /// No connection is `offline`; any other failure keeps its network-layer cause.
    private func networkFailure(_ error: APIError) -> AuthError {
        if case .transport = error {
            return .offline
        }
        return .server(error)
    }

    private func isUserAlreadyExists(_ body: Data?) -> Bool {
        guard let body, let serverError = try? JSONDecoder.app.decode(ServerErrorDTO.self, from: body) else {
            return false
        }
        return serverError.reason == "User already exists"
    }
}
