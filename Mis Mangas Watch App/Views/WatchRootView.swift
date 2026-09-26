//
//  WatchRootView.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI

/// Shows the reading list once one has arrived from the iPhone, and until then how to get one.
struct WatchRootView: View {
    /// Written by the coordinator when a reading list arrives; the view follows the change. Read
    /// from the standard defaults, which the coordinator writes to when it is given no suite.
    @AppStorage(WatchSessionCoordinator.lastSnapshotKey) private var lastSnapshotAt: Date?

    var body: some View {
        NavigationStack {
            if lastSnapshotAt == nil {
                WatchSignedOutView(isSynced: false)
            } else {
                WatchReadingListView()
            }
        }
    }
}

// No preview: with Xcode 27 every watchOS preview that contains a `NavigationStack` crashes in
// UIKit layout before drawing, in the canvas too, while the app runs this same view on the same
// simulator without trouble. Both screens it can show have their own previews:
// `WatchSignedOutView` ("Not synced") and `WatchReadingListView`. Restore this preview once
// previews render a `NavigationStack` on watchOS.
//
// #Preview("Not synced", traits: .emptyStore) {
//     WatchRootView()
// }
