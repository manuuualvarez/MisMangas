//
//  RootView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Root of the app's view tree: the welcome screen without a session, the tabs as a guest or
/// signed in. A sign-in in progress stays on the welcome screen, whose form shows the wait and
/// keeps what was typed. At launch and on every change of session, the sync coordinator moves to
/// the service of that session and the maintenance runs, with a first pass when signed in.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SessionViewModel.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .idle, .authenticating, .failed:
                WelcomeView()
            case .guest, .authenticated:
                MainTabView()
            }
        }
        .task(id: session.isAuthenticated) {
            await dependencies.applySession(authenticated: session.isAuthenticated)
            // The session changed again meanwhile: the task that replaced this one runs the rest.
            guard !Task.isCancelled else { return }
            await dependencies.bootstrap()
        }
    }
}

#Preview("Root", traits: .sampleData) {
    RootView()
}
