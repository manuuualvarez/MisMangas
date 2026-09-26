//
//  AppDependencies.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import Observation
import SwiftData
import WatchConnectivity

/// The app's long-lived services, built once and handed to the view tree through the
/// environment (`@Environment(AppDependencies.self)`). Only the session of the sync coordinator
/// changes after creation; the class shape is what the environment needs to hold it by type.
@Observable
@MainActor
final class AppDependencies {
    let container: ModelContainer
    let syncActor: MangaSyncActor
    let mangaRepository: any MangaRepository
    let security: any SecurityData
    let taxonomyCache: TaxonomyCacheActor
    /// Reaches the user's collection on the server; only the signed-in service uses it.
    let collectionRepository: any CollectionRepository
    /// The service the screens use: saving, removing, the catalog and the detail work on the
    /// device the same way with or without a session.
    let syncService: MangaSyncService
    /// The only one in the app, so two passes never drain the queue in parallel. It gets the
    /// signed-in service while there is a session.
    let syncCoordinator: SyncCoordinator
    let session: SessionViewModel
    /// Keeps the watch's reading list current; `nil` on a device that cannot pair a watch.
    let watchSync: WatchSyncService?
    /// Keeps the reading widget's covers and timeline current.
    let readingWidget: ReadingWidgetService
    /// Whether the coordinator runs the signed-in service.
    private(set) var isSessionActive = false
    /// The service for a session: signed in to an account, it reaches the user's collection on the server
    /// through `collectionRepository`; as a guest, the collection stays on the device.
    private let makeSyncService: @MainActor (String?) -> MangaSyncService

    init(
        container: ModelContainer,
        mangaRepository: any MangaRepository,
        security: any SecurityData = Security(),
        collectionRepository: (any CollectionRepository)? = nil,
        defaults: UserDefaults = .standard
    ) {
        // Views never save; every write is an explicit `save()` inside `MangaSyncActor`.
        container.mainContext.autosaveEnabled = false
        self.container = container
        self.mangaRepository = mangaRepository
        self.security = security
        syncActor = MangaSyncActor(modelContainer: container)
        taxonomyCache = TaxonomyCacheActor(mangaRepository: mangaRepository)
        let collectionRepository = collectionRepository ?? DefaultCollectionRepository(security: security)
        self.collectionRepository = collectionRepository
        syncService = MangaSyncService(syncActor: syncActor, mangaRepository: mangaRepository, taxonomyCache: taxonomyCache)
        syncCoordinator = SyncCoordinator(service: syncService)
        makeSyncService = { [syncActor, taxonomyCache] account in
            MangaSyncService(
                syncActor: syncActor,
                mangaRepository: mangaRepository,
                taxonomyCache: taxonomyCache,
                collectionRepository: account == nil ? nil : collectionRepository,
                account: account
            )
        }
        session = SessionViewModel(
            security: security,
            syncCoordinator: syncCoordinator,
            syncActor: syncActor,
            defaults: defaults,
            makeSyncService: makeSyncService
        )
        watchSync = WCSession.isSupported()
            ? WatchSyncService(
                transport: WatchSessionBridge(),
                syncActor: syncActor,
                syncCoordinator: syncCoordinator,
                sessionState: { [session] in (account: session.account, isSignedOut: session.isWelcomeRequired) }
            )
            : nil
        readingWidget = ReadingWidgetService(
            syncActor: syncActor,
            syncCoordinator: syncCoordinator,
            // Without the shared folder the widget still reloads, without covers.
            coverCache: CoverCacheFiles.appGroup.map { CoverCacheService(files: $0) }
        )
    }

    /// Follows a change of session: the coordinator stops the passes of the previous one and
    /// continues with the service of the new one. Returns a subscription to the events of the new
    /// session only.
    @discardableResult
    func applySession(account: String?) async -> AsyncStream<SyncEvent> {
        isSessionActive = account != nil
        return await syncCoordinator.replaceService(makeSyncService(account))
    }

    /// The control state of a screen that edits or syncs the collection: the screens' service, the
    /// app's coordinator and the session whose account stamps every change. Only the screen that
    /// shows the refusal notice presents it.
    func makeCollectionViewModel(presentsRejections: Bool) -> CollectionViewModel {
        CollectionViewModel(
            syncService: syncService,
            syncCoordinator: syncCoordinator,
            session: session,
            presentsRejections: presentsRejections
        )
    }

    /// The real store in the App Group container and the real backend.
    static func live() throws(PersistenceError) -> AppDependencies {
        try AppDependencies(container: PersistenceController.makeContainer(), mangaRepository: DefaultMangaRepository())
    }

    /// Maintenance of the store, and a pass when there is a session. Runs at launch and after every
    /// change of session; the purges it does are cheap when there is nothing to purge.
    func bootstrap() async {
        _ = await syncService.bootstrap()
        if isSessionActive {
            await syncCoordinator.requestSync()
        }
    }
}
