//
//  PreviewSecurity.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

/// Account backend for previews: sign-in and sign-up accept, fail with a chosen error or keep
/// waiting, without a network and without the Keychain, so a preview can show every state of the
/// welcome forms. There is never a stored session: restoring finds nothing and any renewal
/// expires.
struct PreviewSecurity: SecurityData {
    enum Behavior {
        case accepts
        case fails(AuthError)
        /// Never answers while the preview is on screen, to show the wait.
        case waits
    }

    let behavior: Behavior
    /// Required by the protocol; every requirement that would read or write it is replaced here,
    /// so previews never touch the Keychain.
    let store: any SecureStore = SecKeyStore(service: "cloud.manuelalvarez.Mis-Mangas.preview")

    nonisolated init(behavior: Behavior = .accepts) {
        self.behavior = behavior
    }

    func appToken() throws(AuthError) -> String {
        "preview"
    }

    func currentToken() throws(AuthError) -> String? {
        nil
    }

    func storedEmail() throws(AuthError) -> String? {
        nil
    }

    func register(email _: String, password _: String) async throws(AuthError) {
        try await answer()
    }

    func login(email _: String, password _: String) async throws(AuthError) {
        try await answer()
    }

    func refresh() async throws(AuthError) {
        throw .sessionExpired
    }

    func validToken() async throws(AuthError) -> String {
        throw .sessionExpired
    }

    func me() async throws(AuthError) -> UserResponse {
        throw .sessionExpired
    }

    func clearToken() throws(AuthError) {}

    func logout() throws(AuthError) {}

    func validateJWT(_: String) throws(AuthError) -> JWTPayload {
        throw .invalidToken
    }

    private func answer() async throws(AuthError) {
        switch behavior {
        case .accepts:
            return
        case let .fails(error):
            throw error
        case .waits:
            // A preview lives far less than this; when it goes away the sleep is cancelled and
            // the answer no longer matters.
            try? await Task.sleep(for: .seconds(3600))
        }
    }
}
