//
//  WatchSignedOutView.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI

/// What the watch shows without a reading list: before the iPhone has sent any, or when the last
/// one it sent was empty (nothing being read, or signed out on the iPhone).
struct WatchSignedOutView: View {
    /// A reading list has arrived from the iPhone at least once.
    let isSynced: Bool

    var body: some View {
        if isSynced {
            ContentUnavailableView {
                Label("Nothing in progress", systemImage: "books.vertical")
            } description: {
                Text("The mangas you're reading on your iPhone appear here.")
            }
        } else {
            ContentUnavailableView {
                Label("Not synced yet", systemImage: "iphone")
            } description: {
                Text("Open Mis Mangas on your iPhone to sync your reading list")
            }
        }
    }
}

#Preview("Not synced") {
    WatchSignedOutView(isSynced: false)
}

#Preview("Nothing in progress") {
    WatchSignedOutView(isSynced: true)
}
