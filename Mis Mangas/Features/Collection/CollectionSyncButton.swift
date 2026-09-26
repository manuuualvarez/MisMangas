//
//  CollectionSyncButton.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 25/09/2026.
//

import SwiftUI

/// Syncs the collection now, so pulling the list is never the only way. A badge shows how many
/// changes still wait to reach the server.
struct CollectionSyncButton: View {
    let pendingCount: Int
    let action: () -> Void

    var body: some View {
        Button("Sync now", systemImage: "arrow.triangle.2.circlepath", action: action)
            .badge(pendingCount)
            // The badge takes the accessibility value ("1 item"), so the label says what it counts.
            .accessibilityLabel(pendingCount > 0 ? Text("Sync now, ^[\(pendingCount) change](inflect: true) waiting") : Text("Sync now"))
            .accessibilityInputLabels([Text("Sync now"), Text("Sync")])
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        Text(verbatim: "")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CollectionSyncButton(pendingCount: 3) {}
                }
            }
    }
}
