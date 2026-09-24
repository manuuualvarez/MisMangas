//
//  URLSession+Authenticated.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

extension URLSession {
    /// Session for the requests that carry the user's token: no cookies, credentials or
    /// responses are written to disk, so account and collection data only live in the Keychain
    /// and the store.
    static let authenticated: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
}
