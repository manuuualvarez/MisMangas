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
    /// Made anew for every manga the screen shows, so no refresh state carries over.
    @State private var viewModel: MangaDetailViewModel?
    /// Only the refresh the reader asked for reports its failure; an automatic one leaves the
    /// cached record on screen without a word.
    @State private var isShowingRefreshError = false
    /// Lets the refresh button bring the progress line and its error, on top of the content,
    /// into view.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                MangaRefreshStatusView(
                    isRefreshing: viewModel?.isRefreshing ?? false,
                    error: isShowingRefreshError ? viewModel?.refreshError : nil
                ) {
                    Task { await refreshManually() }
                }
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
        .scrollPosition($scrollPosition)
        .navigationTitle(manga.title)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            // A button and not pull to refresh: on iPhone, pulling down from the top of a screen
            // opened with a zoom transition closes it.
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    withAnimation(reduceMotion ? nil : .default) {
                        scrollPosition.scrollTo(edge: .top)
                    }
                    Task { await refreshManually() }
                }
                .disabled(viewModel?.isRefreshing ?? true)
            }
        }
        .sheet(isPresented: $isEditingCollection) {
            CollectionEditorSheet(manga: manga, syncService: dependencies.syncService)
        }
        .task(id: selected.id) {
            let model = MangaDetailViewModel(syncService: dependencies.syncService)
            viewModel = model
            isShowingRefreshError = false
            await model.refreshIfNeeded(manga: manga)
        }
    }

    private func refreshManually() async {
        guard let viewModel else {
            return
        }
        await viewModel.refresh(manga: manga)
        // Another manga took the screen meanwhile: its state is not this refresh's to touch.
        guard viewModel === self.viewModel else {
            return
        }
        isShowingRefreshError = viewModel.refreshError != nil
        if let description = viewModel.refreshError?.errorDescription {
            AccessibilityNotification.Announcement(description).post()
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

// Monster never cached: the screen fetches it from the server and shows "Updating…" meanwhile.
#Preview("Refreshing", traits: .emptyStore()) {
    NavigationStack {
        if let monster = SampleData.mangas.first(where: { $0.id == 1 }) { MangaDetailView(manga: monster.makeManga()) }
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
