//
//  MangaDetailView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// The full record of a manga, read from the store: header, the collection button with the
/// reader's progress, volumes and chapters, authors, tags and synopsis. Sections without data
/// are left out. The button opens the collection form as a sheet. A record handed over by the
/// list stays as it was fetched even after the store changes, so the screen queries it again by
/// id: every write from the form (or a refresh from the server) shows without leaving the screen.
struct MangaDetailView: View {
    /// The manga the list selected: the identity of the screen and the fallback until the query
    /// answers.
    private let selected: Manga
    @Query private var stored: [Manga]

    @State private var isEditingCollection = false
    @Environment(AppDependencies.self) private var dependencies

    init(manga: Manga) {
        selected = manga
        let id = manga.id
        _stored = Query(filter: #Predicate<Manga> { $0.id == id })
    }

    private var manga: Manga {
        stored.first ?? selected
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MangaHeaderView(manga: manga)
                Button {
                    isEditingCollection = true
                } label: {
                    Label(
                        manga.inCollection ? "Edit in My Collection" : "Add to My Collection",
                        systemImage: manga.inCollection ? "pencil" : "plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                MangaCollectionStatusView(manga: manga)
                MangaStatisticsView(volumes: manga.volumes, chapters: manga.chapters)
                if !manga.authors.isEmpty {
                    MangaAuthorsView(authors: manga.orderedAuthors)
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
        .sheet(isPresented: $isEditingCollection) {
            CollectionEditorSheet(manga: manga, syncService: dependencies.syncService)
        }
    }
}

// Dr. Slump: not in the collection.
#Preview("Not in collection", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    NavigationStack {
        if let manga = mangas.first(where: { $0.id == 796 }) { MangaDetailView(manga: manga) }
    }
}

// Dragon Ball: every field present; in the collection, reading volume 7 of 42.
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
