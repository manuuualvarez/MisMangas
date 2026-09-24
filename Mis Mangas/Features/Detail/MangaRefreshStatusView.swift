//
//  MangaRefreshStatusView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import SwiftUI

/// A quiet line on top of the detail while the record is being fetched again (a retry included),
/// or the error of a refresh the reader asked for, with its retry. It takes no room otherwise.
struct MangaRefreshStatusView: View {
    let isRefreshing: Bool
    let error: APIError?
    let retry: () -> Void

    var body: some View {
        if isRefreshing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Updating…")
                    .font(.footnote)
                    .foregroundStyle(.mmSecondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if let error {
            InlineErrorView(error: error, retry: retry)
        }
    }
}

#Preview("Updating", traits: .sampleData) {
    MangaRefreshStatusView(isRefreshing: true, error: nil) {}
        .padding()
}

#Preview("Failed refresh", traits: .sampleData) {
    MangaRefreshStatusView(isRefreshing: false, error: .transport(URLError(.notConnectedToInternet))) {}
        .padding()
}
