//
//  MangaCardView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// One catalog row: cover, title, first author and score, read as a single accessibility element.
/// The cover is the source of the zoom transition into the detail. At accessibility text sizes
/// the text moves under the cover and the title is no longer clipped.
struct MangaCardView: View {
    let manga: Manga
    let namespace: Namespace.ID

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            MangaCoverView(manga: manga, size: .small)
                .matchedTransitionSource(id: manga.id, in: namespace)
            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if let author = manga.primaryAuthorName {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.mmSecondaryLabel)
                }
                Label(manga.formattedScore, systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.mmSecondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(manga.catalogAccessibilityLabel)
    }
}

#Preview("Card", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Namespace var namespace
    if let manga = mangas.first { MangaCardView(manga: manga, namespace: namespace).padding() }
}
