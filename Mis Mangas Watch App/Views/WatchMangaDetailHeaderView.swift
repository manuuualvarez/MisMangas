//
//  WatchMangaDetailHeaderView.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftData
import SwiftUI

/// The top of a manga's watch screen: a small cover beside the title, so the reading controls
/// below fit on the first screen.
struct WatchMangaDetailHeaderView: View {
    let manga: Manga

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility text sizes the title moves under the cover, where it has the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            // The title right beside it says the same; one swipe less on the watch.
            MangaCoverView(manga: manga, size: .thumbnail)
                .accessibilityHidden(true)
            Text(manga.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Clear of the screen's curved edges and in line with the controls below.
        .scenePadding(.minimum, edges: .horizontal)
    }
}

// Dragon Ball.
#Preview("Header", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first(where: { $0.id == 42 }) { WatchMangaDetailHeaderView(manga: manga) }
}
