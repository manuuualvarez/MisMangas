//
//  APIError.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Every failure the networking layer can surface. `Error` refines `Sendable`, so this enum is
/// implicitly `Sendable` and crosses from `@APIActor` to `@MainActor` without further annotation.
enum APIError: LocalizedError {
    case invalidURL
    case transport(any Error)
    case encoding(any Error)
    case decoding(any Error)
    case http(status: Int, body: Data?)
    case unauthorized
    case forbidden
    case notFound
    case serverError
    case cancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The request address is not valid.")
        case .transport:
            String(localized: "The network is unavailable. Check your connection and try again.")
        case .encoding:
            String(localized: "The request could not be prepared.")
        case .decoding:
            String(localized: "The server response could not be read.")
        case .http(let status, _):
            String(localized: "The server responded with an unexpected status (\(status)).")
        case .unauthorized:
            String(localized: "Your session has expired. Please sign in again.")
        case .forbidden:
            String(localized: "You do not have permission to do that.")
        case .notFound:
            String(localized: "The requested content was not found.")
        case .serverError:
            String(localized: "The server is having trouble. Please try again later.")
        case .cancelled:
            String(localized: "The request was cancelled.")
        case .unknown:
            String(localized: "Something went wrong. Please try again.")
        }
    }

    /// 4xx statuses and their semantic counterparts: shown to the user, never retried.
    var isClientError: Bool {
        switch self {
        case .http(let status, _):
            (400..<500).contains(status)
        case .unauthorized, .forbidden, .notFound:
            true
        default:
            false
        }
    }

    /// 5xx statuses and their semantic counterpart.
    var isServerError: Bool {
        switch self {
        case .http(let status, _):
            (500..<600).contains(status)
        case .serverError:
            true
        default:
            false
        }
    }

    /// Transient failures worth retrying: transport problems and server-side errors.
    var isRetryable: Bool {
        switch self {
        case .transport:
            true
        default:
            isServerError
        }
    }
}
