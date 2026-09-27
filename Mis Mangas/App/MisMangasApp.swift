//
//  MisMangasApp.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 11/09/2026.
//

import OSLog
import SwiftData
import SwiftUI

@main
struct MisMangasApp: App {
    /// The store either opened or not: the app never crashes on a persistence failure, it shows
    /// the error and offers a retry.
    @State private var startup: Result<AppDependencies, PersistenceError>

    init() {
        // The launch interval opens here, as early as the app runs its own code; the root view
        // ends it once it knows which screen to show. One launch per process: an exclusive id,
        // from which the root view recreates the interval state, so nothing is kept here.
        _ = OSSignposter.app.beginInterval(SignpostName.launch, id: .exclusive)
        _startup = State(initialValue: Self.start())
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case let .success(dependencies):
                RootView()
                    .modelContainer(dependencies.container)
                    .environment(dependencies)
                    .environment(dependencies.session)
            case let .failure(error):
                PersistenceFailureView(error: error) {
                    startup = Self.start()
                }
            }
        }
    }

    private static func start() -> Result<AppDependencies, PersistenceError> {
        let startup = Result { () throws(PersistenceError) in
            try AppDependencies.live()
        }
        if case let .success(dependencies) = startup {
            // The widget follows the collection from launch, on every device: the passes a watch
            // change asks for in the background reach it too. `start()` only launches the listening
            // task and returns.
            Task {
                await dependencies.readingWidget.start()
            }
            if let watchSync = dependencies.watchSync {
                // The watch session starts with the app, not with a screen: a message from the watch
                // can launch the app in the background without connecting any scene.
                Task {
                    await watchSync.start()
                }
            }
        }
        return startup
    }
}
