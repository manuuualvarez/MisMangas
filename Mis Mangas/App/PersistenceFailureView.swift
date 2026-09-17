//
//  PersistenceFailureView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Shown instead of the app when the local store cannot be opened.
struct PersistenceFailureView: View {
    let error: PersistenceError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Your library is unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            if let description = error.errorDescription {
                Text(description)
            }
        } actions: {
            Button("Retry") {
                retry()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Container unavailable", traits: .sampleData) {
    PersistenceFailureView(error: .containerUnavailable(APIError.unknown)) {}
}
