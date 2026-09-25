//
//  RootView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Root of the app's view tree. At launch it waits, without showing any screen, until the
/// session of an earlier launch resumes or not; then the welcome screen without a session, the tabs
/// as a guest or signed in. A sign-in in progress stays where it started, on the welcome screen or
/// in the guest's tabs, so its form shows the wait, keeps what was typed and shows a failure. Once the launch has decided, and on every change of session, the
/// sync coordinator moves to the service of that session and the maintenance runs, with a first
/// pass when signed in; back in the foreground, a signed-in app syncs again.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SessionViewModel.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    /// Whether the dependencies follow a signed-in session; none while the launch is restoring.
    private var settledAuthentication: Bool? {
        session.state == .restoring ? nil : session.isAuthenticated
    }

    var body: some View {
        Group {
            // One branch for the tabs, so a guest who signs in keeps the tab and the screen they
            // were on.
            if session.state == .restoring {
                RestoringSessionView()
            } else if session.isWelcomeRequired {
                WelcomeView()
            } else {
                MainTabView()
            }
        }
        .task {
            await session.restoreSession()
        }
        .task(id: settledAuthentication) {
            guard let authenticated = settledAuthentication else { return }
            await dependencies.applySession(authenticated: authenticated)
            // The session changed again meanwhile: the task that replaced this one runs the rest.
            guard !Task.isCancelled else { return }
            await dependencies.bootstrap()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, dependencies.isSessionActive else { return }
            await dependencies.syncCoordinator.requestSync()
        }
    }
}

#Preview("Root", traits: .sampleData) {
    RootView()
}
