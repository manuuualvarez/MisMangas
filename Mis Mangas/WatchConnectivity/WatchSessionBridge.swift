//
//  WatchSessionBridge.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import WatchConnectivity

/// Adapts the system connectivity session to `WatchTransport`. `WCSessionDelegate` is an
/// Objective-C protocol and its conformer must inherit from `NSObject`: this is the only
/// Objective-C class of the app, and nothing of it leaks past the `events` stream.
///
/// The system calls the delegate on a background thread, one call at a time; each call only
/// reads the message and yields it. Calling the session before it is activated is a programming
/// error, so both sends check it first. The message format lives in `WatchPayload`.
final class WatchSessionBridge: NSObject, WCSessionDelegate, WatchTransport {
    let events: AsyncStream<WatchSessionEvent>
    private let continuation: AsyncStream<WatchSessionEvent>.Continuation

    override init() {
        (events, continuation) = AsyncStream.makeStream(of: WatchSessionEvent.self)
        super.init()
    }

    var hasContentPending: Bool {
        WCSession.default.hasContentPending
    }

    func activate() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func updateApplicationContext(_ snapshot: ReadingSnapshot) throws(WatchTransportError) {
        let session = try activatedSession()
        let dictionary = try WatchPayload.readingSnapshot(snapshot).dictionary()
        do {
            try session.updateApplicationContext(dictionary)
        } catch {
            throw (error as? WCError)?.code == .payloadTooLarge ? .payloadTooLarge : .underlying(error)
        }
    }

    /// Sends the change by both channels: a message, delivered at once while the iPhone app is
    /// running, and the queued transfer, delivered even if the iPhone is out of reach. The
    /// iPhone ignores the copy that arrives second, because it is not later than the first.
    func send(_ update: ReadingUpdate) throws(WatchTransportError) {
        let session = try activatedSession()
        let dictionary = try WatchPayload.readingUpdate(update).dictionary()
        if session.isReachable {
            session.sendMessage(dictionary, replyHandler: nil)
        }
        _ = session.transferUserInfo(dictionary)
    }

    private func activatedSession() throws(WatchTransportError) -> WCSession {
        let session = WCSession.default
        guard session.activationState == .activated else {
            throw .notActivated
        }
        return session
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        // A session that did not activate cannot be used; the next launch tries again.
        guard activationState == .activated else {
            return
        }
        continuation.yield(.activated(isReachable: session.isReachable))
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        continuation.yield(.reachabilityChanged(isReachable: session.isReachable))
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // A context this version cannot read (another version of the app) is dropped.
        guard case let .readingSnapshot(snapshot)? = try? WatchPayload(dictionary: applicationContext) else {
            return
        }
        continuation.yield(.readingSnapshot(snapshot))
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveUpdate(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receiveUpdate(userInfo)
    }

    private func receiveUpdate(_ dictionary: [String: Any]) {
        // A message this version cannot read (another version of the app) is dropped.
        guard case let .readingUpdate(update)? = try? WatchPayload(dictionary: dictionary) else {
            return
        }
        continuation.yield(.readingUpdate(update))
    }

    #if os(iOS)
    /// Required on iOS; nothing to do while the iPhone switches to another watch.
    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The iPhone switched to another watch: the session is activated again for it.
    func sessionDidDeactivate(_ session: WCSession) {
        continuation.yield(.deactivated)
        WCSession.default.activate()
    }
    #endif
}
