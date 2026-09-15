//
//  MangaCardView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// One catalog row: cover, title, first author and score, read as a single accessibility element.
/// The cover is the source of the zoom transition into the detail.
struct MangaCardView: View {
    let manga: Manga
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            MangaCoverView(manga: manga, size: .small)
                .matchedTransitionSource(id: manga.id, in: namespace)
            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(2)
                if let author = manga.primaryAuthorName {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Label(manga.formattedScore, systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(manga.catalogAccessibilityLabel)
    }
}

#Preview("Card", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Namespace var namespace
    if let manga = mangas.first { MangaCardView(manga: manga, namespace: namespace).padding() }
}
