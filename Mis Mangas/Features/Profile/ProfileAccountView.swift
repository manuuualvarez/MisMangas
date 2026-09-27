//
//  ProfileAccountView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// The signed-in profile: the account's email, the collection's sync status (kept current while
/// on screen, whichever pass ends) with "Sync now" and the retry of blocked changes, and the
/// sign-out. Signing out asks first and says how many unsent changes it discards; the collection
/// itself stays on the device.
struct ProfileAccountView: View {
    let email: String
    @Environment(SessionViewModel.self) private var session
    @State private var viewModel: CollectionViewModel
    @State private var isSignOutConfirmationPresented = false

    init(email: String, dependencies: AppDependencies) {
        self.email = email
        _viewModel = State(initialValue: dependencies.makeCollectionViewModel(presentsRejections: false))
    }

    var body: some View {
        @Bindable var session = session
        Form {
            Section {
                LabeledContent("Email") {
                    Text(email)
                        .foregroundStyle(.mmSecondaryLabel)
                }
            } header: {
                // The system gray of headers falls below 4.5:1 on the grouped background.
                Text("Account")
                    .foregroundStyle(.mmSecondaryLabel)
            }
            ProfileSyncStatusView(
                pendingCount: viewModel.pendingCount,
                blockedCount: viewModel.blockedCount,
                lastSyncDate: viewModel.lastSyncDate,
                isSyncing: viewModel.isSyncing
            ) {
                Task {
                    await viewModel.synchronize()
                    if let announcement = viewModel.syncAnnouncement {
                        AccessibilityNotification.Announcement(announcement).post()
                    }
                }
            } retryBlocked: {
                Task {
                    await viewModel.retryBlocked()
                    if let announcement = viewModel.syncAnnouncement {
                        AccessibilityNotification.Announcement(announcement).post()
                    }
                }
            }
            Section {
                Button("Sign Out", role: .destructive) {
                    Task {
                        // The warning counts what is unsent right now, not when the tab opened.
                        await session.refreshPendingChanges()
                        isSignOutConfirmationPresented = true
                    }
                }
                // The system red falls below 4.5:1 on a light row.
                .foregroundStyle(.mmDestructive)
            }
        }
        .task {
            await viewModel.observePasses()
        }
        // An alert, not a dialog anchored to the row: it keeps a visible Cancel on every device.
        .alert("Sign out?", isPresented: $isSignOutConfirmationPresented) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await session.signOut()
                    // The whole screen gives way to the welcome screen; say why.
                    if !session.isAuthenticated {
                        // High priority: the welcome screen replacing this one would cut it short.
                        var announcement = AttributedString(localized: "Signed out")
                        announcement.accessibilitySpeechAnnouncementPriority = .high
                        AccessibilityNotification.Announcement(announcement).post()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if session.unsentChangesCount > 0 {
                Text("^[\(session.unsentChangesCount) unsent change](inflect: true) will be discarded. Your collection stays on this device until another account signs in.")
            } else {
                Text("Your collection stays on this device until another account signs in.")
            }
        }
        .alert(
            "Couldn't sync",
            isPresented: $viewModel.isSyncErrorPresented,
            presenting: viewModel.syncError
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert("Couldn't sign out", isPresented: $session.isSignOutFailurePresented) {
            Button("OK") {}
        } message: {
            Text("Something went wrong while signing out, so you're still signed in. Try again.")
        }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    NavigationStack {
        ProfileAccountView(email: "reader@example.com", dependencies: dependencies)
    }
}
