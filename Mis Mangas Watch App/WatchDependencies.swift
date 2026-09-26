//
//  WatchDependencies.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Observation
import SwiftData

/// The watch app's long-lived pieces, built once: its own store (the iPhone's cannot be reached
/// from the watch), its only writer and the session with the iPhone. Each screen builds its own
/// view model from `syncActor` and `coordinator`.
@Observable
@MainActor
final class WatchDependencies {
    let container: ModelContainer
    let syncActor: MangaSyncActor
    let coordinator: WatchSessionCoordinator

    init(container: ModelContainer, transport: any WatchTransport) {
        // Views never save; every write is an explicit `save()` inside `MangaSyncActor`.
        container.mainContext.autosaveEnabled = false
        self.container = container
        syncActor = MangaSyncActor(modelContainer: container)
        coordinator = WatchSessionCoordinator(transport: transport, syncActor: syncActor)
    }

    /// The watch's own store and the real session with the iPhone.
    static func live() throws(PersistenceError) -> WatchDependencies {
        try WatchDependencies(container: PersistenceController.makeLocalContainer(), transport: WatchSessionBridge())
    }
}
