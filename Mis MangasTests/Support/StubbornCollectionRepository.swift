//
//  StubbornCollectionRepository.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 25/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Synchronization

/// A `CollectionRepository` whose uploads ignore cancellation: each `upsert` waits, even after its
/// pass is stopped, until the test answers it with `release(throwing:)`. It reproduces a server
/// answer that arrives after the session changed, which a real `URLSession` would usually cut short.
/// `waitUntilHeld()` returns once an upload waits; `waitUntilCancelled()` once its pass was stopped.
/// The server collection is always empty. A test that holds an upload must release it: a stopped pass
/// waits for it, which is the very case the double exists for.
struct StubbornCollectionRepository: CollectionRepository {
    private struct State {
        var held: CheckedContinuation<APIError?, Never>?
        var isCancelled = false
        var heldWaiters: [CheckedContinuation<Void, Never>] = []
        var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    }

    /// Holds the lock: a struct cannot store a `Mutex`, which is not copyable.
    private final class Box: Sendable {
        let state = Mutex(State())
    }

    let security: any SecurityData
    let session: URLSession
    private let box = Box()

    nonisolated init(security: any SecurityData) {
        self.security = security
        session = URLSessionMockInterface.makeSession()
    }

    func fetchCollection() async throws(APIError) -> [UserMangaCollectionDTO] {
        []
    }

    func upsert(_ request: UserMangaCollectionRequest) async throws(APIError) {
        let answer = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<APIError?, Never>) in
                let waiters = box.state.withLock { state in
                    state.held = continuation
                    let waiters = state.heldWaiters
                    state.heldWaiters = []
                    return waiters
                }
                waiters.forEach { $0.resume() }
            }
        } onCancel: {
            let waiters = box.state.withLock { state in
                state.isCancelled = true
                let waiters = state.cancelWaiters
                state.cancelWaiters = []
                return waiters
            }
            waiters.forEach { $0.resume() }
        }
        if let answer {
            throw answer
        }
    }

    func delete(mangaID: Int) async throws(APIError) {}

    nonisolated func waitUntilHeld() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isHeld = box.state.withLock { state in
                if state.held != nil {
                    return true
                }
                state.heldWaiters.append(continuation)
                return false
            }
            if isHeld {
                continuation.resume()
            }
        }
    }

    nonisolated func waitUntilCancelled() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isCancelled = box.state.withLock { state in
                if state.isCancelled {
                    return true
                }
                state.cancelWaiters.append(continuation)
                return false
            }
            if isCancelled {
                continuation.resume()
            }
        }
    }

    /// Answers the waiting upload: accepted, or failed with `error`.
    nonisolated func release(throwing error: APIError? = nil) {
        let held = box.state.withLock { state in
            let held = state.held
            state.held = nil
            return held
        }
        held?.resume(returning: error)
    }
}
