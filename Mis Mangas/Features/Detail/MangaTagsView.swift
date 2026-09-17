//
//  MangaTagsView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// Demographics, genres and themes as read-only chips that wrap into as many rows as needed.
struct MangaTagsView: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitleView(title: "Tags")
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { ChipView(text: $0) }
            }
        }
    }
}

#Preview("Tags", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaTagsView(tags: manga.demographics + manga.genres + manga.themes).padding() }
}
