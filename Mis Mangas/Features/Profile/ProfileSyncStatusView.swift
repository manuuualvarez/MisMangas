//
//  ProfileSyncStatusView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// How many collection changes still wait to reach the server, and how many it kept refusing.
/// The blocked row only shows when there is one.
struct ProfileSyncStatusView: View {
    let pendingCount: Int
    let blockedCount: Int

    var body: some View {
        Section("Sync") {
            LabeledContent("Pending changes") {
                Text(pendingCount, format: .number)
            }
            if blockedCount > 0 {
                LabeledContent("Couldn't be synced") {
                    Text(blockedCount, format: .number)
                        .foregroundStyle(.mmWarning)
                }
            }
        }
    }
}

#Preview("Nothing unsent", traits: .sampleData) {
    Form {
        ProfileSyncStatusView(pendingCount: 0, blockedCount: 0)
    }
}

#Preview("Pending and blocked", traits: .sampleData) {
    Form {
        ProfileSyncStatusView(pendingCount: 3, blockedCount: 1)
    }
}
