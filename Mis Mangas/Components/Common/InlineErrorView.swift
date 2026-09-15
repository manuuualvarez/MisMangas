//
//  InlineErrorView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// A one-row failure notice with a retry action, for lists that keep their content on error.
struct InlineErrorView: View {
    let error: any LocalizedError
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let description = error.errorDescription {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Retry") {
                retry()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

#Preview("Server error", traits: .sampleData) {
    InlineErrorView(error: APIError.serverError) {}
        .padding()
}
