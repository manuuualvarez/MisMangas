//
//  WatchApp.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftData
import SwiftUI

@main
struct WatchApp: App {
    /// The store either opened or not: the app never crashes on a persistence failure.
    @State private var startup: Result<WatchDependencies, PersistenceError> = Result { () throws(PersistenceError) in
        try WatchDependencies.live()
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case let .success(dependencies):
                WatchRootView()
                    .modelContainer(dependencies.container)
                    .environment(dependencies)
                    .task {
                        await dependencies.coordinator.start()
                    }
            case let .failure(error):
                ContentUnavailableView(
                    "Your library is unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(error.localizedDescription)
                )
            }
        }
        // Woken in the background by what the iPhone sent: the task ends once it is applied.
        .backgroundTask(.watchConnectivity) { [coordinator] in
            await coordinator?.receivePendingContent()
        }
    }

    private var coordinator: WatchSessionCoordinator? {
        guard case let .success(dependencies) = startup else {
            return nil
        }
        return dependencies.coordinator
    }
}
