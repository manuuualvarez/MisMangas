//
//  MangaTagsView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// Demographics, genres and themes as chips that wrap into as many rows as needed. Each chip
/// filters the catalog that shows this detail by its category.
struct MangaTagsView: View {
    let demographics: [String]
    let genres: [String]
    let themes: [String]
    /// Grows with the text size, so large chips do not read as one block.
    @ScaledMetric private var chipSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitleView(title: "Tags")
            FlowLayout(spacing: chipSpacing) {
                ForEach(demographics, id: \.self) { name in
                    FilterChipView(
                        mode: .byDemographic(name),
                        accessibilityLabel: String(localized: "\(name), demographic"),
                        hint: "Shows mangas for this demographic"
                    )
                }
                ForEach(genres, id: \.self) { name in
                    FilterChipView(
                        mode: .byGenre(name),
                        accessibilityLabel: String(localized: "\(name), genre"),
                        hint: "Shows mangas with this genre"
                    )
                }
                ForEach(themes, id: \.self) { name in
                    FilterChipView(
                        mode: .byTheme(name),
                        accessibilityLabel: String(localized: "\(name), theme"),
                        hint: "Shows mangas with this theme"
                    )
                }
            }
        }
    }
}

#Preview("Tags", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first(where: { $0.id == 2 }) {
        MangaTagsView(demographics: manga.demographics, genres: manga.genres, themes: manga.themes).padding()
    }
}
