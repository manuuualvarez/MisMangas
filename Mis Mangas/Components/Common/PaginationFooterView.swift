//
//  PaginationFooterView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Footer of a paginated list: which page is loading out of how many, or a note when there is
/// no page left.
struct PaginationFooterView: View {
    let isLoading: Bool
    let hasNextPage: Bool
    /// The page being requested while `isLoading`.
    let page: Int
    let totalPages: Int?

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    loadingText
                }
            } else if !hasNextPage {
                Text("No more results")
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var loadingText: Text {
        if let totalPages {
            Text("Loading page \(page, format: .number) of \(totalPages, format: .number)…")
        } else {
            Text("Loading page \(page, format: .number)…")
        }
    }
}

#Preview("Loading", traits: .sampleData) {
    PaginationFooterView(isLoading: true, hasNextPage: true, page: 2, totalPages: 3242)
}

#Preview("End of results", traits: .sampleData) {
    PaginationFooterView(isLoading: false, hasNextPage: false, page: 3, totalPages: 2)
}
