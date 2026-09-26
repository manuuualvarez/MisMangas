//
//  ProfileGuestView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// The profile in guest mode: the collection lives only on this device, and an account would
/// sync it. Offers the two ways into one.
struct ProfileGuestView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Sign in to sync your collection", systemImage: "icloud.slash")
        } description: {
            Text("Your collection is saved on this device only.")
        } actions: {
            // The size applies to each control: set on the whole view it does not reach them.
            NavigationLink(value: AuthRoute.signIn) {
                Text("Sign In")
            }
            .buttonStyle(.borderedProminent)
            .tint(.mmAccentFill)
            .controlSize(.large)
            NavigationLink(value: AuthRoute.signUp) {
                Text("Create Account")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            // Over the tinted fill of a bordered button the accent falls below 4.5:1 in dark mode;
            // the primary label color stays legible in every appearance.
            .foregroundStyle(.primary)
        }
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        ProfileGuestView()
    }
}
