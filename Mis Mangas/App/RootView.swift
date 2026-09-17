//
//  RootView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Root of the app's view tree. Runs the start-up maintenance once, then shows the tabs.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        MainTabView()
            .task {
                await dependencies.bootstrap()
            }
    }
}

#Preview("Root", traits: .sampleData) {
    RootView()
}
