//
//  AppDependencies.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Observation
import SwiftData

/// The app's long-lived services, built once and handed to the view tree through the
/// environment (`@Environment(AppDependencies.self)`). Immutable after creation; the class shape
/// is what the environment needs to hold it by type.
@Observable
@MainActor
final class AppDependencies {
    let container: ModelContainer
    let syncActor: MangaSyncActor
    let mangaRepository: any MangaRepository
    let syncService: MangaSyncService

    init(container: ModelContainer, mangaRepository: any MangaRepository) {
        // Views never save; every write is an explicit `save()` inside `MangaSyncActor`.
        container.mainContext.autosaveEnabled = false
        self.container = container
        self.mangaRepository = mangaRepository
        syncActor = MangaSyncActor(modelContainer: container)
        syncService = MangaSyncService(
            syncActor: syncActor,
            mangaRepository: mangaRepository,
            taxonomyCache: TaxonomyCacheActor(mangaRepository: mangaRepository)
        )
    }

    /// The real store in the App Group container and the real backend.
    static func live() throws(PersistenceError) -> AppDependencies {
        try AppDependencies(container: PersistenceController.makeContainer(), mangaRepository: DefaultMangaRepository())
    }

    /// Start-up maintenance, once per launch.
    func bootstrap() async {
        _ = await syncService.bootstrap()
    }
}
