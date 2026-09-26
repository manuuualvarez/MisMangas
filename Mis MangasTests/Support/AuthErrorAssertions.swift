//
//  AuthErrorAssertions.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// Comparable shape of an `AuthError` (the production enum wraps `APIError`, which carries
/// `any Error` payloads and is not `Equatable`). `keychain` compares the status; `server`
/// compares the wrapped error through `APIErrorCase`.
enum AuthErrorCase: CustomStringConvertible {
    case invalidEmail
    case weakPassword
    case invalidCredentials
    case sessionExpired
    case invalidToken
    case emailAlreadyRegistered
    case keychain(OSStatus)
    case offline
    case server(APIErrorCase)

    func matches(_ error: AuthError) -> Bool {
        switch (self, error) {
        case (.invalidEmail, .invalidEmail),
             (.weakPassword, .weakPassword),
             (.invalidCredentials, .invalidCredentials),
             (.sessionExpired, .sessionExpired),
             (.invalidToken, .invalidToken),
             (.emailAlreadyRegistered, .emailAlreadyRegistered),
             (.offline, .offline):
            true
        case (.keychain(let expected), .keychain(let status)):
            expected == status
        case (.server(let expected), .server(let apiError)):
            expected.matches(apiError)
        default:
            false
        }
    }

    var description: String {
        switch self {
        case .invalidEmail: "invalidEmail"
        case .weakPassword: "weakPassword"
        case .invalidCredentials: "invalidCredentials"
        case .sessionExpired: "sessionExpired"
        case .invalidToken: "invalidToken"
        case .emailAlreadyRegistered: "emailAlreadyRegistered"
        case .keychain(let status): "keychain(\(status))"
        case .offline: "offline"
        case .server(let apiError): "server(\(apiError))"
        }
    }
}

/// Runs `operation` and records an issue unless it throws an `AuthError` matching `expected`.
/// Returns the thrown `AuthError` (if any) so callers can inspect payloads.
@discardableResult
func expectAuthError<Value>(
    _ expected: AuthErrorCase,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: () async throws -> Value
) async -> AuthError? {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    do {
        _ = try await operation()
        Issue.record("Expected AuthError.\(expected), but the operation completed", sourceLocation: sourceLocation)
        return nil
    } catch {
        return expectAuthError(expected, matches: error, at: sourceLocation)
    }
}

/// Synchronous counterpart for operations that do not suspend.
@discardableResult
func expectAuthError<Value>(
    _ expected: AuthErrorCase,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: () throws -> Value
) -> AuthError? {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    do {
        _ = try operation()
        Issue.record("Expected AuthError.\(expected), but the operation completed", sourceLocation: sourceLocation)
        return nil
    } catch {
        return expectAuthError(expected, matches: error, at: sourceLocation)
    }
}

private func expectAuthError(_ expected: AuthErrorCase, matches error: any Error, at sourceLocation: SourceLocation) -> AuthError? {
    guard let authError = error as? AuthError else {
        Issue.record("Expected AuthError.\(expected), got \(error)", sourceLocation: sourceLocation)
        return nil
    }
    #expect(expected.matches(authError), "Expected AuthError.\(expected), got AuthError.\(authError)", sourceLocation: sourceLocation)
    return authError
}
