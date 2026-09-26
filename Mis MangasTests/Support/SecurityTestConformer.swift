//
//  SecurityTestConformer.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas

/// Test conformer of `SecurityData`. It replaces only the seams: the `store` (an
/// `InMemorySecureStore` the test reads as its oracle), the `session` inherited from
/// `NetworkInteractor` (transport = `URLSessionMockInterface`) and the `App-Token` value (a test
/// literal instead of the one injected into `Info.plist` at build time). Every operation —
/// `register`, `login`, `refresh`, `validToken`, `me`, `clearToken`, `logout`, `validateJWT` —
/// is the production code of `extension SecurityData`.
struct SecurityTestConformer: SecurityData {
    let store: any SecureStore
    let session: URLSession
    private let appTokenValue: String

    nonisolated init(store: any SecureStore, appToken: String) {
        self.store = store
        self.appTokenValue = appToken
        session = URLSessionMockInterface.makeSession()
    }

    func appToken() throws(AuthError) -> String {
        appTokenValue
    }
}
