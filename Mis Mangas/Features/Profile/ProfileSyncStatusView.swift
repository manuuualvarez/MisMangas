//
//  ProfileSyncStatusView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// The collection's sync status: when it last reached the server (kept current every minute), how
/// many changes still wait to go up and how many it kept refusing, with a way to sync now and, when
/// some are set aside, to retry them. The blocked row only shows when there is one; while a sync
/// runs, its buttons wait.
struct ProfileSyncStatusView: View {
    let pendingCount: Int
    let blockedCount: Int
    let lastSyncDate: Date?
    let isSyncing: Bool
    let syncNow: () -> Void
    let retryBlocked: () -> Void

    var body: some View {
        Section("Sync") {
            LabeledContent("Last sync") {
                if let lastSyncDate {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text(lastSyncDate, format: .relative(presentation: .named))
                            .foregroundStyle(.mmSecondaryLabel)
                    }
                } else {
                    Text("Not yet")
                        .foregroundStyle(.mmSecondaryLabel)
                }
            }
            LabeledContent("Pending changes") {
                Text(pendingCount, format: .number)
                    .foregroundStyle(.mmSecondaryLabel)
            }
            if blockedCount > 0 {
                // The warning color marks the symbol; the text keeps the row's own hierarchy.
                Label {
                    Text("^[\(blockedCount) change](inflect: true) couldn't be synced")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.mmWarning)
                }
                Button("Retry blocked changes", action: retryBlocked)
                    .disabled(isSyncing)
            }
            Button(action: syncNow) {
                LabeledContent("Sync now") {
                    if isSyncing {
                        // The button's value already says "Syncing".
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
            }
            .disabled(isSyncing)
            .accessibilityValue(isSyncing ? Text("Syncing") : Text(verbatim: ""))
        }
    }
}

#Preview("Never synced", traits: .sampleData) {
    Form {
        ProfileSyncStatusView(pendingCount: 0, blockedCount: 0, lastSyncDate: nil, isSyncing: false, syncNow: {}, retryBlocked: {})
    }
}

#Preview("Pending and blocked", traits: .sampleData) {
    Form {
        ProfileSyncStatusView(
            pendingCount: 3,
            blockedCount: 1,
            lastSyncDate: .now.addingTimeInterval(-3600),
            isSyncing: false,
            syncNow: {},
            retryBlocked: {}
        )
    }
}

#Preview("Syncing", traits: .sampleData) {
    Form {
        ProfileSyncStatusView(pendingCount: 2, blockedCount: 0, lastSyncDate: .now, isSyncing: true, syncNow: {}, retryBlocked: {})
    }
}
