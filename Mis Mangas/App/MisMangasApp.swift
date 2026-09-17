//
//  MisMangasApp.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 11/09/2026.
//

import SwiftData
import SwiftUI

@main
struct MisMangasApp: App {
    /// The store either opened or not: the app never crashes on a persistence failure, it shows
    /// the error and offers a retry.
    @State private var startup: Result<AppDependencies, PersistenceError>

    init() {
        _startup = State(initialValue: Self.start())
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case let .success(dependencies):
                RootView()
                    .modelContainer(dependencies.container)
                    .environment(dependencies)
            case let .failure(error):
                PersistenceFailureView(error: error) {
                    startup = Self.start()
                }
            }
        }
    }

    private static func start() -> Result<AppDependencies, PersistenceError> {
        Result { () throws(PersistenceError) in
            try AppDependencies.live()
        }
    }
}
