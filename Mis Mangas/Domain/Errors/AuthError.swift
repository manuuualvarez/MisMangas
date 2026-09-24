//
//  AuthError.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// Every failure of the account and session flow. `Error` refines `Sendable`, so the enum crosses
/// from `@APIActor` to `@MainActor` without further annotation.
enum AuthError: LocalizedError {
    /// The email does not look like an address; detected before touching the network.
    case invalidEmail
    /// The password is shorter than the backend minimum of 8 characters.
    case weakPassword
    /// `POST /users/jwt/login` answered 401.
    case invalidCredentials
    /// There is no usable token: it expired, could not be renewed or was never stored.
    case sessionExpired
    /// A JWT that cannot be read: not three segments, invalid base64url or JSON, or missing
    /// `exp`, `email` or `user_id`.
    case invalidToken
    /// `POST /users` answered 400 with the reason "User already exists".
    case emailAlreadyRegistered
    /// Keychain Services returned a status other than success (or "not found" on reads).
    case keychain(OSStatus)
    /// The device has no connection.
    case offline
    /// Any other failure of the network layer.
    case server(APIError)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            String(localized: "Enter a valid email")
        case .weakPassword:
            String(localized: "Password must be at least 8 characters")
        case .invalidCredentials:
            String(localized: "Incorrect email or password")
        case .sessionExpired:
            String(localized: "Your session expired. Please sign in again.")
        case .invalidToken:
            String(localized: "The server returned an invalid session. Please try again.")
        case .emailAlreadyRegistered:
            String(localized: "This email is already registered")
        case .keychain:
            String(localized: "Couldn't store your session securely")
        case .offline:
            String(localized: "You're offline. Try again when connected.")
        case .server(let error):
            error.errorDescription
        }
    }
}
