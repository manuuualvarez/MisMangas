//
//  WatchTransportError.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

/// Failures of the connection with the other device. None reaches the screen as it is: the watch
/// says in its own words that a change was not sent.
enum WatchTransportError: Error {
    /// The session is not active yet, so nothing can be sent.
    case notActivated
    case encoding(any Error)
    case decoding(any Error)
    /// The message does not have the expected shape (it may come from another version of the app).
    case unrecognizedPayload
    case payloadTooLarge
    /// Any other failure reported by the system session.
    case underlying(any Error)
}
