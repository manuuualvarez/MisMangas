//
//  WatchMangaRowView.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftData
import SwiftUI

/// One manga of the reading list: cover, title and how far the reader has got, read as a single
/// accessibility element with the progress spelled out ("Vol." is read letter by letter).
struct WatchMangaRowView: View {
    let manga: Manga

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility text sizes the text moves under the cover, where it has the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            MangaCoverView(manga: manga, size: .thumbnail)
            VStack(alignment: .leading, spacing: 2) {
                Text(manga.title)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                if let progress = manga.collectionProgressText {
                    Text(progress)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(manga.collectionAccessibilityLabel)
        // Voice Control users say the title they see, not the whole spoken label.
        .accessibilityInputLabels([Text(manga.title)])
    }
}

// Dragon Ball: reading volume 7 of 42.
#Preview("Reading", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first(where: { $0.id == 42 }) { WatchMangaRowView(manga: manga) }
}
