//
//  EmptyStateView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Placeholder for a list with nothing to show. With a `refresh` action it offers a button, so
/// reloading never depends on the pull-to-refresh gesture alone.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var description: String?
    var refresh: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        } actions: {
            if let refresh {
                Button("Refresh") {
                    refresh()
                }
                .buttonStyle(.borderedProminent)
                .tint(.mmAccentFill)
                .controlSize(.large)
            }
        }
    }
}

#Preview("Empty catalog", traits: .sampleData) {
    EmptyStateView(title: "No mangas yet", systemImage: "books.vertical", description: "Pull to refresh to load the catalog.") {}
}
