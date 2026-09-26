//
//  FakeWatchTransport.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

#if os(watchOS)
@testable import Mis_Mangas_Watch_App
#else
@testable import Mis_Mangas
#endif
import Synchronization

/// Scripted `WatchTransport` for the layers above the connectivity session (the iPhone sync
/// service, the watch coordinator and ViewModel), whose tests need to see what was sent and to
/// decide what arrives from the other device. Nothing reaches `WCSession`.
///
/// Every call is recorded: `activateCalls`, `publishedSnapshots` and `sentUpdates`, in call order.
/// With `contextError` or `sendError` set, `updateApplicationContext` or `send` throws that error
/// and records nothing, as a payload that never left the device.
///
/// `emit(_:)` delivers an event through `events` as the session would; `finish()` ends the stream,
/// so a consumer loop over `events` returns.
///
/// Configure with `configure { $0.… = … }`. Reads are synchronous and usable from any isolation.
final class FakeWatchTransport: WatchTransport {
    struct Behavior {
        /// Thrown by `updateApplicationContext`, which then records nothing.
        var contextError: WatchTransportError?
        /// Thrown by `send`, which then records nothing.
        var sendError: WatchTransportError?
        /// What `hasContentPending` reports.
        var hasContentPending = false
    }

    private struct State {
        var behavior = Behavior()
        var activateCalls = 0
        var publishedSnapshots: [ReadingSnapshot] = []
        var sentUpdates: [ReadingUpdate] = []
    }

    let events: AsyncStream<WatchSessionEvent>
    private let continuation: AsyncStream<WatchSessionEvent>.Continuation
    private let state = Mutex(State())

    init() {
        let (events, continuation) = AsyncStream.makeStream(of: WatchSessionEvent.self)
        self.events = events
        self.continuation = continuation
    }

    // MARK: - Test controls

    func configure(_ change: (inout Behavior) -> Void) {
        state.withLock { change(&$0.behavior) }
    }

    /// Delivers `event` to whoever consumes `events`.
    func emit(_ event: WatchSessionEvent) {
        continuation.yield(event)
    }

    /// Ends `events`: a loop consuming it returns after the events already emitted.
    func finish() {
        continuation.finish()
    }

    var activateCalls: Int {
        state.withLock { $0.activateCalls }
    }

    /// The snapshots published with `updateApplicationContext`, in call order.
    var publishedSnapshots: [ReadingSnapshot] {
        state.withLock { $0.publishedSnapshots }
    }

    /// The updates sent with `send`, in call order.
    var sentUpdates: [ReadingUpdate] {
        state.withLock { $0.sentUpdates }
    }

    // MARK: - WatchTransport

    var hasContentPending: Bool {
        state.withLock { $0.behavior.hasContentPending }
    }

    func activate() {
        state.withLock { $0.activateCalls += 1 }
    }

    func updateApplicationContext(_ snapshot: ReadingSnapshot) throws(WatchTransportError) {
        try state.withLock { state -> Result<Void, WatchTransportError> in
            if let error = state.behavior.contextError {
                return .failure(error)
            }
            state.publishedSnapshots.append(snapshot)
            return .success(())
        }.get()
    }

    func send(_ update: ReadingUpdate) throws(WatchTransportError) {
        try state.withLock { state -> Result<Void, WatchTransportError> in
            if let error = state.behavior.sendError {
                return .failure(error)
            }
            state.sentUpdates.append(update)
            return .success(())
        }.get()
    }
}
