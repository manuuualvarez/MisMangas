//
//  ProfileView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// The Profile tab: the account and its unsent changes when signed in; as a guest, the way into
/// an account. A sign-in started here returns to the tab's root once it succeeds, which then shows
/// the account.
struct ProfileView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if case let .authenticated(email) = session.state {
                    ProfileAccountView(email: email)
                } else {
                    ProfileGuestView()
                }
            }
            .navigationTitle("Profile")
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .signIn:
                    SignInView()
                case .signUp:
                    SignUpView()
                }
            }
        }
        .onChange(of: session.isAuthenticated) {
            path.removeAll()
        }
    }
}

#Preview("Guest", traits: .sampleData) {
    @Previewable @Environment(SessionViewModel.self) var session
    ProfileView()
        .task { session.continueAsGuest() }
}

#Preview("Signed in", traits: .sampleData) {
    @Previewable @Environment(SessionViewModel.self) var session
    ProfileView()
        .task { await session.signIn(email: "reader@example.com", password: "preview-password") }
}
