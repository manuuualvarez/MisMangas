//
//  CollectionRowView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// One row of My Collection: cover, title, how far the reader has got and a "Complete" badge,
/// read as a single accessibility element. The state color goes on the symbols; the text keeps
/// the primary color, which the system turns white over a selected row. At accessibility text
/// sizes the text moves under the cover and the title is no longer clipped. The cover is the
/// source of the zoom transition into the detail.
struct CollectionRowView: View {
    let manga: Manga
    let namespace: Namespace.ID
    /// Over the accent fill of a selected row the state colors all but vanish, so the symbols
    /// take the primary color the system turns white there, like the text.
    var isSelected = false

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
                if let progress = manga.collectionProgressText {
                    Label {
                        Text(progress)
                    } icon: {
                        Image(systemName: "book.fill")
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.mmWarning))
                    }
                    .font(.subheadline)
                }
                if manga.collectionEntry?.completeCollection == true {
                    Label {
                        Text("Complete")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.mmSuccess))
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(manga.collectionAccessibilityLabel)
    }
}

// Dragon Ball: reading volume 7 of 42.
#Preview("Reading", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Namespace var namespace
    if let manga = mangas.first(where: { $0.id == 42 }) { CollectionRowView(manga: manga, namespace: namespace).padding() }
}

// Monster: complete, without a reading volume.
#Preview("Complete", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    @Previewable @Namespace var namespace
    if let manga = mangas.first(where: { $0.id == 1 }) { CollectionRowView(manga: manga, namespace: namespace).padding() }
}
