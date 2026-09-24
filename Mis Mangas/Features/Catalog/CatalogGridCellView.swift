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
/// Titles reserve two lines so the covers of a row stay aligned; at accessibility text sizes
/// (one wide column) they get room to wrap instead. A selected cell (the manga shown in the
/// detail column) outlines its cover with the accent color.
struct CatalogGridCellView: View {
    let manga: Manga
    let namespace: Namespace.ID
    var isSelected = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The selection outline grows with the text size, so it stays visible next to larger cells.
    @ScaledMetric(relativeTo: .subheadline) private var selectionLineWidth: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MangaCoverView(manga: manga, size: .fill, showsScore: true)
                .matchedTransitionSource(id: manga.id, in: namespace)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.tint, lineWidth: isSelected ? selectionLineWidth : 0)
                }
            Text(manga.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(
                    dynamicTypeSize.isAccessibilitySize ? 4 : 2,
                    reservesSpace: !dynamicTypeSize.isAccessibilitySize
                )
                .multilineTextAlignment(.leading)
            if let author = manga.primaryAuthorName {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.mmSecondaryLabel)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(manga.catalogAccessibilityLabel)
        // Voice Control users say the title they see, not the whole spoken label.
        .accessibilityInputLabels([Text(manga.title)])
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Cell", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Namespace var namespace
    if let manga = mangas.first { CatalogGridCellView(manga: manga, namespace: namespace).frame(width: 120) }
}

#Preview("Selected", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Namespace var namespace
    if let manga = mangas.first { CatalogGridCellView(manga: manga, namespace: namespace, isSelected: true).frame(width: 120) }
}
