//
//  InlineErrorView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// A one-row failure notice with a retry action, for lists that keep their content on error.
/// At accessibility text sizes the message and the button stack, so neither gets squeezed.
struct InlineErrorView: View {
    let error: any LocalizedError
    let retry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let description = error.errorDescription {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.mmSecondaryLabel)
            }
            // Only the row layout has room to push the button to the trailing edge.
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            Button("Retry") {
                retry()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, 4)
    }
}

#Preview("Server error", traits: .sampleData) {
    InlineErrorView(error: APIError.serverError) {}
        .padding()
}
