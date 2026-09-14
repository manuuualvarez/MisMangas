//
//  PaginationFooterView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Footer of a paginated list: a spinner while the next page loads, a note when there is none.
struct PaginationFooterView: View {
    let isLoading: Bool
    let hasNextPage: Bool

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView()
                    .accessibilityLabel("Loading more mangas")
            } else if !hasNextPage {
                Text("No more results")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview("Loading", traits: .sampleData) {
    PaginationFooterView(isLoading: true, hasNextPage: true)
}

#Preview("End of results", traits: .sampleData) {
    PaginationFooterView(isLoading: false, hasNextPage: false)
}
