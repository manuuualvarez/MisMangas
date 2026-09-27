//
//  ReadingWidgetService.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import OSLog
import WidgetKit

/// Keeps the reading widget current: at launch and at the end of every synchronization pass it
/// brings the covers up to date and then asks the system to reload the widget.
///
/// Every change of the collection ends in a pass: a local save or removal asks for one, and so
/// does every change applied from the watch; a guest's pass ends without reaching the server. One
/// reload per pass, never per entry, keeps the widget within its daily reload budget.
actor ReadingWidgetService {
    private let syncActor: MangaSyncActor
    private let syncCoordinator: SyncCoordinator
    /// `nil` when the shared folder is not available: the widget still reloads, without covers.
    private let coverCache: CoverCacheService?
    private let reload: @Sendable () -> Void
    /// Follows the passes for the life of the process: whoever called `start()` may go away without
    /// stopping it.
    private var listening: Task<Void, Never>?

    init(
        syncActor: MangaSyncActor,
        syncCoordinator: SyncCoordinator,
        coverCache: CoverCacheService?,
        reload: @escaping @Sendable () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: .readingWidgetKind) }
    ) {
        self.syncActor = syncActor
        self.syncCoordinator = syncCoordinator
        self.coverCache = coverCache
        self.reload = reload
    }

    /// Starts following the synchronization passes, then returns. Only the first call does anything.
    func start() {
        guard listening == nil else {
            return
        }
        listening = Task {
            // Subscribed before the first refresh, so no pass that ends meanwhile goes unheard.
            // Passes that end during a refresh all say the same thing: only the newest waits.
            let passes = await syncCoordinator.events(bufferingPolicy: .bufferingNewest(1))
            // A guest's launch has no pass: the widget catches up here.
            await refresh()
            // One event at a time: a refresh never overlaps another.
            for await event in passes {
                if case .passFinished = event {
                    await refresh()
                }
            }
        }
    }

    /// The covers first, so the widget finds them when it reads the store after the reload.
    private func refresh() async {
        do {
            let snapshot = try await syncActor.readingSnapshot(limit: ReadingItemsFetcher.itemLimit)
            await coverCache?.update(to: snapshot.items)
        } catch {
            // The covers stay as they were; the widget reads the store on its own.
            Logger.widget.error("Reading list not read for the widget: \(String(describing: error))")
        }
        reload()
    }
}
