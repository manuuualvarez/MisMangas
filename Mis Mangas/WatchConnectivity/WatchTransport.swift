//
//  WatchTransport.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

/// The connection between the iPhone app and the watch app. Sending only queues the payload;
/// what arrives from the other side comes through `events`.
protocol WatchTransport: Sendable {
    var events: AsyncStream<WatchSessionEvent> { get }
    /// Whether the session received content in the background that it has not delivered yet.
    var hasContentPending: Bool { get }
    func activate()
    /// Replaces the reading list the watch will receive; only the latest one is delivered.
    func updateApplicationContext(_ snapshot: ReadingSnapshot) throws(WatchTransportError)
    /// Sends a change made on the watch; it reaches the iPhone even if it is not reachable now.
    func send(_ update: ReadingUpdate) throws(WatchTransportError)
}
