//
//  MangaCollectionStatusView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// One line under the collection button of the detail, for a manga in the collection: complete,
/// or how far the reader has got. The state color goes on the symbol; the text keeps the
/// secondary label color so it stays legible at any size.
struct MangaCollectionStatusView: View {
    let manga: Manga

    var body: some View {
        if let entry = manga.collectionEntry {
            Label {
                if entry.completeCollection {
                    Text("Complete collection")
                } else if let progress = manga.collectionProgressText {
                    Text(progress)
                }
            } icon: {
                if entry.completeCollection {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.mmSuccess)
                } else {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.mmWarning)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.mmSecondaryLabel)
            .frame(maxWidth: .infinity)
        }
    }
}

// Dragon Ball: reading volume 7 of 42.
#Preview("Reading", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first(where: { $0.id == 42 }) { MangaCollectionStatusView(manga: manga).padding() }
}

// Monster: complete.
#Preview("Complete", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first(where: { $0.id == 1 }) { MangaCollectionStatusView(manga: manga).padding() }
}
