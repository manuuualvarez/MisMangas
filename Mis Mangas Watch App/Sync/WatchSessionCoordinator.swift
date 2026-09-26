//
//  WatchSessionCoordinator.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// The watch side of the connection: applies every reading list the iPhone publishes to the
/// watch's own store and remembers when the last one arrived.
actor WatchSessionCoordinator {
    /// Where the date of the last reading list received is kept.
    static let lastSnapshotKey = "watch.lastSnapshotAt"
    /// How often `receivePendingContent()` looks again while something is still on its way.
    private static let pendingCheckInterval: Duration = .milliseconds(50)

    private let transport: any WatchTransport
    private let syncActor: MangaSyncActor
    /// Created here rather than passed in: `UserDefaults` is not `Sendable`.
    private let defaults: UserDefaults
    /// Applies the events of the session one at a time, for the life of the coordinator.
    private var listening: Task<Void, Never>?
    private var isActivated = false
    /// A reading list is being written to the store.
    private var isApplying = false

    /// `defaultsSuiteName` names the defaults that keep the arrival date; `nil` uses the app's own.
    init(transport: any WatchTransport, syncActor: MangaSyncActor, defaultsSuiteName: String? = nil) {
        self.transport = transport
        self.syncActor = syncActor
        defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// When the last reading list arrived; `nil` until the first one.
    var lastSnapshotAt: Date? {
        defaults.object(forKey: Self.lastSnapshotKey) as? Date
    }

    /// Activates the session and starts applying what arrives; later calls change nothing.
    func start() {
        guard listening == nil else {
            return
        }
        let events = transport.events
        // Listening starts before activating, so nothing the session delivers goes unread.
        listening = Task {
            for await event in events {
                await handle(event)
            }
        }
        transport.activate()
    }

    /// Returns once the session is active and everything the iPhone sent in the background has
    /// been received and applied, or when the calling task is cancelled (the system ran out of
    /// background time). The session hands content over before it clears `hasContentPending`;
    /// looking again after a short pause lets the listening task take what it was handed.
    func receivePendingContent() async {
        start()
        var isSettled = false
        while !Task.isCancelled {
            let isIdle = isActivated && !transport.hasContentPending && !isApplying
            if isIdle, isSettled {
                return
            }
            isSettled = isIdle
            do {
                try await Task.sleep(for: Self.pendingCheckInterval)
            } catch {
                return
            }
        }
    }

    private func handle(_ event: WatchSessionEvent) async {
        switch event {
        case .activated:
            isActivated = true
        case .deactivated:
            isActivated = false
        case .readingSnapshot(let snapshot):
            isApplying = true
            defer { isApplying = false }
            do {
                try await syncActor.applyReadingSnapshot(snapshot)
                defaults.set(Date.now, forKey: Self.lastSnapshotKey)
            } catch {
                // The store kept the previous list; the next list the iPhone publishes replaces it.
            }
        case .reachabilityChanged, .readingUpdate:
            break
        }
    }
}
