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
/// in the guest's tabs, so its form shows the wait, keeps what was typed and shows a failure. Once
/// the launch has decided, and on every change of account, the sync coordinator moves to the
/// service of that account and the maintenance runs, with a first pass when signed in; back in the
/// foreground, a signed-in app syncs again. A pass that finds the session rejected by the server,
/// whoever asked for it, ends the session here. The watch's reading list follows the session.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(SessionViewModel.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    /// The account the dependencies follow (`nil` inside: no account); nothing while the launch is
    /// restoring.
    private var settledAccount: String?? {
        session.state == .restoring ? nil : .some(session.account)
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
        .task {
            await dependencies.watchSync?.start()
        }
        .task(id: session.isWelcomeRequired) {
            // Signing out empties the watch's list; choosing a guest or signing in fills it again.
            await dependencies.watchSync?.publishSnapshot()
        }
        .task(id: settledAccount) {
            guard case .some(let account) = settledAccount else { return }
            // Listening starts with the session itself: every pass of this session is heard, and
            // none of the previous one.
            let events = await dependencies.applySession(account: account)
            // The session changed again meanwhile: the task that replaced this one runs the rest.
            guard !Task.isCancelled else { return }
            await dependencies.bootstrap()
            for await event in events {
                if case .sessionExpired = event {
                    await session.expire()
                }
            }
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
