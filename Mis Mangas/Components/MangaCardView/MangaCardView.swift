//
//  MangaCardView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// One catalog row: cover, title, first author and score, read as a single accessibility element.
struct MangaCardView: View {
    let manga: Manga

    var body: some View {
        HStack(spacing: 12) {
            MangaCoverView(manga: manga, size: .small)
            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(2)
                if let author = manga.primaryAuthorName {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Label(formattedScore, systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var formattedScore: String {
        manga.score.formatted(.number.precision(.fractionLength(2)))
    }

    private var accessibilityLabel: String {
        if let author = manga.primaryAuthorName {
            String(localized: "\(manga.title), by \(author), score \(formattedScore)")
        } else {
            String(localized: "\(manga.title), score \(formattedScore)")
        }
    }
}

#Preview("Card", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaCardView(manga: manga).padding() }
}
