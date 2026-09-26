//
//  WelcomeActionsView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// The three ways out of the welcome screen: sign in, create an account or continue as a guest.
struct WelcomeActionsView: View {
    @Environment(SessionViewModel.self) private var session

    var body: some View {
        VStack(spacing: 12) {
            NavigationLink(value: AuthRoute.signIn) {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mmAccentFill)
            NavigationLink(value: AuthRoute.signUp) {
                Text("Create Account")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            // Over the tinted fill of a bordered button the accent falls below 4.5:1 in dark mode;
            // the primary label color stays legible in every appearance.
            .foregroundStyle(.primary)
            Button {
                session.continueAsGuest()
            } label: {
                Text("Continue without account")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityHint("Your collection stays on this device")
        }
        .controlSize(.large)
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        WelcomeActionsView()
            .padding()
    }
}
