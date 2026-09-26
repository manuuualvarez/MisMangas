//
//  WatchSyncService.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// The iPhone side of the watch connection: publishes the reading list to the watch whenever the
/// collection may have changed, and applies the reading volumes chosen on the watch.
///
/// Every synchronization pass ends with a publication: each local change of the collection asks
/// for a pass, and so does every change applied from the watch. A change of session publishes
/// through `publishSnapshot()` directly.
actor WatchSyncService {
    /// The most recently changed mangas the watch receives; the rest stay on the iPhone.
    static let snapshotLimit = 50

    private let transport: any WatchTransport
    private let syncActor: MangaSyncActor
    private let syncCoordinator: SyncCoordinator
    /// The account that stamps the changes received from the watch, and whether the app is signed
    /// out, which publishes an empty list.
    private let sessionState: @MainActor @Sendable () -> (account: String?, isSignedOut: Bool)
    /// Follows the session and the passes for the life of the process: whoever called `start()`
    /// may go away without stopping it.
    private var listening: Task<Void, Never>?
    /// Counts the publications begun, so one that was overtaken while it read never sends.
    private var publication = 0

    init(
        transport: any WatchTransport,
        syncActor: MangaSyncActor,
        syncCoordinator: SyncCoordinator,
        sessionState: @escaping @MainActor @Sendable () -> (account: String?, isSignedOut: Bool)
    ) {
        self.transport = transport
        self.syncActor = syncActor
        self.syncCoordinator = syncCoordinator
        self.sessionState = sessionState
    }

    /// Activates the session and starts following it and the synchronization passes, then returns.
    /// Only the first call does anything.
    func start() {
        guard listening == nil else {
            return
        }
        let sessionEvents = transport.events
        listening = Task {
            // Subscribed before activating, so no pass that ends meanwhile goes unpublished.
            let passes = await syncCoordinator.events()
            transport.activate()
            await listen(to: passes, and: sessionEvents)
        }
    }

    private func listen(to passes: AsyncStream<SyncEvent>, and sessionEvents: AsyncStream<WatchSessionEvent>) async {
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await event in passes {
                    if case .passFinished = event {
                        await self.publishSnapshot()
                    }
                }
            }
            group.addTask {
                // One event at a time: a change is applied before the next one is read.
                for await event in sessionEvents {
                    await self.handle(event)
                }
            }
        }
    }

    /// Publishes the current reading list, or an empty one while signed out; the watch receives
    /// only the latest one. A list that cannot be read or sent is skipped: the next change of the
    /// collection publishes again.
    func publishSnapshot() async {
        publication += 1
        let current = publication
        let snapshot: ReadingSnapshot
        if await sessionState().isSignedOut {
            snapshot = ReadingSnapshot(generatedAt: .now, items: [])
        } else {
            do {
                snapshot = try await syncActor.readingSnapshot(limit: Self.snapshotLimit)
            } catch {
                return
            }
        }
        // Another publication began while this one read: its list is the more recent one, and the
        // watch keeps only the last list it receives.
        guard current == publication else {
            return
        }
        do {
            try transport.updateApplicationContext(snapshot)
        } catch {
            // Not activated yet, or the watch cannot take it now: activation publishes again.
        }
    }

    private func handle(_ event: WatchSessionEvent) async {
        switch event {
        case .activated, .reachabilityChanged(isReachable: true):
            await publishSnapshot()
        case .readingUpdate(let update):
            await apply(update)
        case .reachabilityChanged, .readingSnapshot, .deactivated:
            break
        }
    }

    /// Applies a change made on the watch under the session's account and uploads it with the next
    /// pass. Each change usually arrives twice, by message and by queue: the second copy is not
    /// later than itself and changes nothing. A change that arrives while signed out belongs to a
    /// session that is over and is dropped. The list is published either way, so the watch learns
    /// about a change of its own that the iPhone refused.
    private func apply(_ update: ReadingUpdate) async {
        let state = await sessionState()
        guard !state.isSignedOut else {
            await publishSnapshot()
            return
        }
        let account = state.account
        // A change the store cannot take is dropped; the list published below corrects the watch.
        let isApplied = (try? await syncActor.applyReadingUpdate(
            mangaID: update.mangaID,
            readingVolume: update.readingVolume,
            sentAt: update.sentAt,
            account: account
        )) ?? false
        if isApplied {
            await syncCoordinator.requestSync()
        }
        await publishSnapshot()
    }
}
