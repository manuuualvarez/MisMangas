//
//  ErrorStateView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Shows a failure with its localized description and a retry action.
struct ErrorStateView: View {
    let error: any LocalizedError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
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

#Preview("Server error", traits: .sampleData) {
    ErrorStateView(error: APIError.serverError) {}
}
