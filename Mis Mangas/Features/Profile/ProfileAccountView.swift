//
//  ProfileAccountView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// The signed-in profile: the account's email, the changes that have not reached the server and
/// the sign-out. Signing out asks first and says how many unsent changes it discards; the
/// collection itself stays on the device.
struct ProfileAccountView: View {
    let email: String
    @Environment(SessionViewModel.self) private var session
    @State private var isSignOutConfirmationPresented = false

    var body: some View {
        @Bindable var session = session
        Form {
            Section("Account") {
                LabeledContent("Email", value: email)
            }
            ProfileSyncStatusView(pendingCount: session.pendingCount, blockedCount: session.blockedCount)
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
                .confirmationDialog("Sign out?", isPresented: $isSignOutConfirmationPresented, titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await session.signOut()
                            // The whole screen gives way to the welcome screen; say why.
                            if !session.isAuthenticated {
                                AccessibilityNotification.Announcement("Signed out").post()
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if session.unsentChangesCount > 0 {
                        Text("^[\(session.unsentChangesCount) unsent change](inflect: true) will be discarded. Your collection stays on this device.")
                    } else {
                        Text("Your collection stays on this device.")
                    }
                }
            }
        }
        .task {
            await session.refreshPendingChanges()
        }
        .alert("Couldn't sign out", isPresented: $session.isSignOutFailurePresented) {
            Button("OK") {}
        } message: {
            Text("Something went wrong while signing out, so you're still signed in. Try again.")
        }
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        ProfileAccountView(email: "reader@example.com")
    }
}
