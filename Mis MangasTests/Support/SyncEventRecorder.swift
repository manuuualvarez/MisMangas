//
//  SyncEventRecorder.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 25/09/2026.
//

@testable import Mis_Mangas
import Synchronization

/// Consumes a `SyncCoordinator.events()` subscription the way the app's screens do, and records for
/// each event of the kind it was built for (every event when built for none) the phase of the test
/// in which it arrived, and the events themselves in arrival order.
///
/// A test moves to a new phase with `enter(_:)` right before it lets the pass of that phase end;
/// an event recorded under an earlier phase than expected is one that was emitted too many
/// times. `waitUntilReceived(_:)` returns once that many events arrived, or when the test is
/// cancelled (its time limit), so a missing event fails the test instead of hanging it.
final class SyncEventRecorder: Sendable {
    private struct State {
        var phase = 0
        var phases: [Int] = []
        var events: [SyncEvent] = []
        var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())
    private let kind: SyncEvent?

    init(recording kind: SyncEvent? = .sessionExpired) {
        self.kind = kind
    }

    /// Starts consuming `events`; cancel the returned task at the end of the test.
    func consume(_ events: AsyncStream<SyncEvent>) -> Task<Void, Never> {
        Task {
            for await event in events where self.kind == nil || event == self.kind {
                self.record(event)
            }
        }
    }

    func enter(_ phase: Int) {
        state.withLock { $0.phase = phase }
    }

    /// The events recorded, in arrival order.
    var events: [SyncEvent] {
        state.withLock { $0.events }
    }

    /// The phase each event arrived in, in arrival order.
    var phases: [Int] {
        state.withLock { $0.phases }
    }

    /// Returns once `count` events have arrived, or as soon as the calling task is cancelled.
    func waitUntilReceived(_ count: Int) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let isReady = state.withLock { state -> Bool in
                    if state.phases.count >= count || Task.isCancelled {
                        return true
                    }
                    state.waiters.append((count: count, continuation: continuation))
                    return false
                }
                if isReady {
                    continuation.resume()
                }
            }
        } onCancel: {
            let waiters = self.state.withLock { state in
                let waiters = state.waiters
                state.waiters = []
                return waiters
            }
            for waiter in waiters {
                waiter.continuation.resume()
            }
        }
    }

    private func record(_ event: SyncEvent) {
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.phases.append(state.phase)
            state.events.append(event)
            let received = state.phases.count
            let ready = state.waiters.filter { $0.count <= received }.map(\.continuation)
            state.waiters.removeAll { $0.count <= received }
            return ready
        }
        for continuation in ready {
            continuation.resume()
        }
    }
}
