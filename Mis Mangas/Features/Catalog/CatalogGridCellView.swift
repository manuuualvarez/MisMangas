//
//  CatalogGridCellView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// One grid cell: cover with the score badge, title and first author, read as a single
/// accessibility element. The cover is the source of the zoom transition into the detail.
struct CatalogGridCellView: View {
    let manga: Manga
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MangaCoverView(manga: manga, size: .fill, showsScore: true)
                .matchedTransitionSource(id: manga.id, in: namespace)
            Text(manga.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            if let author = manga.primaryAuthorName {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(Color.mmSecondaryLabel)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(manga.catalogAccessibilityLabel)
    }
}

#Preview("Cell", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Namespace var namespace
    if let manga = mangas.first { CatalogGridCellView(manga: manga, namespace: namespace).frame(width: 120) }
}
