//
//  SyncCoordinator.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

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

    init(service: MangaSyncService) {
        self.service = service
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
    /// any request made while stopping, it is dropped.
    func replaceService(_ service: MangaSyncService) async {
        self.service = service
        await stop()
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
            let result: SyncResult
            do {
                result = try await service.synchronizeCollection()
            } catch {
                needsAnotherPass = false
                return .failure(error)
            }
            // A stopped task never starts another pass.
            if !needsAnotherPass || Task.isCancelled {
                return .success(result)
            }
        }
    }
}
