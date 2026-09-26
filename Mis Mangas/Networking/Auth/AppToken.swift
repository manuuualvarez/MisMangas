//
//  AppToken.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// The `App-Token` that `POST /users` requires. It is injected at build time into the
/// `Info.plist` key `AppToken` and never lives in source code.
enum AppToken {
    /// A missing or empty value is a build misconfiguration, reported as `.server(.unknown)`.
    static func value(bundle: Bundle = .main) throws(AuthError) -> String {
        guard let token = bundle.object(forInfoDictionaryKey: "AppToken") as? String, !token.isEmpty else {
            throw .server(.unknown)
        }
        return token
    }
}
