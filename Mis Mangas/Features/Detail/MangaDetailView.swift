//
//  MangaDetailView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// The full record of a manga, read from the store: header, volumes and chapters, authors,
/// tags and synopsis. Sections without data are left out.
struct MangaDetailView: View {
    let manga: Manga

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MangaHeaderView(manga: manga)
                MangaStatisticsView(volumes: manga.volumes, chapters: manga.chapters)
                if !manga.authors.isEmpty {
                    MangaAuthorsView(authors: manga.authors)
                }
                if manga.hasTags {
                    MangaTagsView(demographics: manga.demographics, genres: manga.genres, themes: manga.themes)
                }
                if let synopsis = manga.synopsis, !synopsis.isEmpty {
                    MangaSynopsisView(synopsis: synopsis)
                }
            }
            .padding()
        }
        .navigationTitle(manga.title)
        .toolbarTitleDisplayMode(.inline)
    }
}

// Dragon Ball: every field present.
#Preview("Complete", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    NavigationStack {
        if let manga = mangas.first(where: { $0.id == 42 }) { MangaDetailView(manga: manga) }
    }
}

// Berserk: no end date ("1989–") and no chapter count ("—").
#Preview("Open dates, missing chapters", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    NavigationStack {
        if let manga = mangas.first(where: { $0.id == 2 }) { MangaDetailView(manga: manga) }
    }
}

// Death Note: short synopsis, shown unfolded.
#Preview("Short synopsis", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    NavigationStack {
        if let manga = mangas.first(where: { $0.id == 21 }) { MangaDetailView(manga: manga) }
    }
}
