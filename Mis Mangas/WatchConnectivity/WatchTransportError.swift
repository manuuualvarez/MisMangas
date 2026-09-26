//
//  WatchTransportError.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// Failures of the connection with the other device. The messages are fixed: the errors they
/// carry describe internals, not something the user can act on.
enum WatchTransportError: LocalizedError {
    /// The session is not active yet, so nothing can be sent.
    case notActivated
    case encoding(any Error)
    case decoding(any Error)
    /// The message does not have the expected shape (it may come from another version of the app).
    case unrecognizedPayload
    case payloadTooLarge
    /// Any other failure reported by the system session.
    case underlying(any Error)

    var errorDescription: String? {
        switch self {
        case .notActivated:
            String(localized: "The connection with your iPhone is not ready yet.")
        case .encoding, .decoding, .unrecognizedPayload:
            String(localized: "The reading list could not be read.")
        case .payloadTooLarge:
            String(localized: "The reading list is too large to send.")
        case .underlying:
            String(localized: "The change could not be sent to your iPhone.")
        }
    }
}
