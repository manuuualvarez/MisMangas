//
//  SyncCoordinator.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation

/// Serializes synchronization passes: at most one is running, and a request that arrives while
/// one runs schedules exactly one more after it, so the pass that follows a save always includes
/// that save. The running task belongs to the coordinator, so a caller that goes away never
/// cancels a pass half-way through the queue.
actor SyncCoordinator {
    private var service: MangaSyncService
    /// The running passes, if any. Its result carries the typed error of the last pass.
    private var running: Task<Result<SyncResult, SyncError>, Never>?
    /// Set by every request; the running task keeps passing while it finds it set.
    private var needsAnotherPass = false
    /// When the last pass that succeeded ended. Screens read it through `status()`, so they all
    /// agree and never mix readings of different moments.
    private var lastSyncDate: Date?
    /// What the last pass that succeeded did.
    private var lastResult: SyncResult?
    /// The mangas whose change the server refused, from every pass since the screen last showed
    /// them: a pass that runs right after another never hides the refusals of the first.
    private var unacknowledgedRejections: [Int] = []
    /// Changes with every session: a reading that awaited across a change is taken again.
    private var sessionGeneration = 0
    /// One stream per subscriber: an `AsyncStream` has a single consumer and ends for good when
    /// that consumer is cancelled, so every listener gets its own.
    private var subscribers: [UUID: AsyncStream<SyncEvent>.Continuation] = [:]

    init(service: MangaSyncService) {
        self.service = service
    }

    /// What the passes end with that the app must act on, from now until the caller stops
    /// iterating. Nothing is kept for later subscribers: whoever must hear about a pass subscribes
    /// before asking for it (the root view does before it hands over a session), and a screen
    /// reads everything when it appears.
    func events() -> AsyncStream<SyncEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SyncEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            // The callback is synchronous and cannot reach the actor itself; `publish` also drops
            // ended streams, so this late removal is only tidiness.
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    /// Asks for a pass and returns at once.
    func requestSync() {
        needsAnotherPass = true
        _ = startIfNeeded()
    }

    /// Asks for a pass and waits for it: returns the result of the last pass the running task
    /// performed. `SyncError.sessionExpired` stops the passes and reaches every waiting caller.
    func synchronize() async throws(SyncError) -> SyncResult {
        needsAnotherPass = true
        return try await startIfNeeded().value.get()
    }

    /// Cancels the running passes and waits until they are over: nothing is sent after it
    /// returns. Required before the session changes (sign-out, a different account), since a
    /// pass holds the operations it drained in memory. The queue keeps what was not sent. A request
    /// made while it stops is dropped; the first one after it returns starts a fresh pass. A task
    /// that a request started while the previous one was ending is stopped too: it returns only
    /// when none is running.
    func stop() async {
        needsAnotherPass = false
        while let task = running {
            task.cancel()
            _ = await task.value
        }
    }

    /// Hands the passes to `service` (the session changed) after stopping the running ones: nothing
    /// is sent through the previous service once it returns. The service is replaced before
    /// stopping, so a request that arrives meanwhile never starts a pass on the previous one; like
    /// any request made while stopping, it is dropped. What the previous session's passes left (the
    /// last pass and the refusals) is forgotten once they are over. Returns a subscription to the
    /// events of the new session, taken in the same step, so its listener hears every pass of that
    /// session and none of the previous one.
    @discardableResult
    func replaceService(_ service: MangaSyncService) async -> AsyncStream<SyncEvent> {
        self.service = service
        // Forgotten before stopping: a reading taken meanwhile already sees the new session whole.
        // The stopped passes cannot write it back, since they record nothing once cancelled.
        sessionGeneration += 1
        lastSyncDate = nil
        lastResult = nil
        unacknowledgedRejections = []
        await stop()
        return events()
    }

    /// The screen showed `shown`; refusals that arrived after it read them stay for the next notice.
    func acknowledgeRejections(_ shown: [Int]) {
        unacknowledgedRejections.removeAll { shown.contains($0) }
    }

    /// The queue of the current session's account (the guest's without one), the last pass and the
    /// refusals not yet shown. The queue is read first, so the rest is at least as recent.
    func status() async throws(PersistenceError) -> SyncStatus {
        var counts: (pending: Int, blocked: Int)
        var generation: Int
        repeat {
            generation = sessionGeneration
            counts = try await service.pendingOperationCounts()
        } while generation != sessionGeneration
        return SyncStatus(
            pendingCount: counts.pending,
            blockedCount: counts.blocked,
            lastSyncDate: lastSyncDate,
            lastResult: lastResult,
            rejections: unacknowledgedRejections
        )
    }

    /// Gives the blocked changes a fresh start and waits for the pass that sends them.
    func retryBlocked() async throws(SyncError) -> SyncResult {
        do {
            try await service.unblockAll()
        } catch {
            throw .persistence(error)
        }
        return try await synchronize()
    }

    private func startIfNeeded() -> Task<Result<SyncResult, SyncError>, Never> {
        if let running {
            return running
        }
        let task = Task { await runPasses() }
        running = task
        return task
    }

    /// Passes until no request arrived during the last one. The check of the flag and the reset
    /// of `running` happen without a suspension in between, so a request never finds a task that
    /// has already decided to stop.
    private func runPasses() async -> Result<SyncResult, SyncError> {
        defer { running = nil }
        while true {
            // A task cancelled before its first pass sends nothing.
            if Task.isCancelled {
                return .success(SyncResult(applied: 0, blocked: 0, rejected: [], upserted: 0, removed: 0))
            }
            needsAnotherPass = false
            // The service this pass runs on: the session may change while it awaits.
            let service = service
            let result: SyncResult
            do {
                result = try await service.synchronizeCollection()
            } catch {
                needsAnotherPass = false
                // A stopped pass belongs to a session that is over: nothing it ends with is news.
                guard !Task.isCancelled else {
                    return .failure(error)
                }
                if case .sessionExpired = error {
                    publish(.sessionExpired)
                }
                publish(.passFinished)
                return .failure(error)
            }
            // A stopped pass or a guest's, which never reaches the server, is no synchronization.
            if !Task.isCancelled, service.isSignedIn {
                record(result)
            }
            if !Task.isCancelled {
                publish(.passFinished)
            }
            // A stopped task never starts another pass.
            if !needsAnotherPass || Task.isCancelled {
                return .success(result)
            }
        }
    }

    /// Hands `event` to every subscriber, forgetting the ones whose stream already ended.
    private func publish(_ event: SyncEvent) {
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield(event) {
                subscribers[id] = nil
            }
        }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    /// Seals a pass that reached its end.
    private func record(_ result: SyncResult) {
        lastSyncDate = .now
        lastResult = result
        for mangaID in result.rejected where !unacknowledgedRejections.contains(mangaID) {
            unacknowledgedRejections.append(mangaID)
        }
    }
}
