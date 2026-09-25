//
//  AppDependencies.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import Observation
import SwiftData

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
    /// Whether the coordinator runs the signed-in service.
    private(set) var isSessionActive = false

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
        self.collectionRepository = collectionRepository ?? DefaultCollectionRepository(security: security)
        syncService = MangaSyncService(syncActor: syncActor, mangaRepository: mangaRepository, taxonomyCache: taxonomyCache)
        syncCoordinator = SyncCoordinator(service: syncService)
        session = SessionViewModel(security: security, syncCoordinator: syncCoordinator, syncActor: syncActor, defaults: defaults)
    }

    /// Follows a change of session: the coordinator stops the passes of the previous one and
    /// continues with the service of the new one.
    func applySession(authenticated: Bool) async {
        isSessionActive = authenticated
        await syncCoordinator.replaceService(makeSyncService(authenticated: authenticated))
    }

    /// The service for a session: signed in, it reaches the user's collection on the server
    /// through `collectionRepository`; as a guest, the collection stays on the device.
    private func makeSyncService(authenticated: Bool) -> MangaSyncService {
        MangaSyncService(
            syncActor: syncActor,
            mangaRepository: mangaRepository,
            taxonomyCache: taxonomyCache,
            collectionRepository: authenticated ? collectionRepository : nil
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
