//
//  WatchReadingListView.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftData
import SwiftUI

/// The mangas being read, most recently updated first, as the iPhone last sent them. The store
/// only changes when a reading list arrives, so the list follows the iPhone on its own.
struct WatchReadingListView: View {
    @Query(
        filter: #Predicate<Manga> { $0.inCollection == true },
        sort: [SortDescriptor(\Manga.updatedAt, order: .reverse)]
    )
    private var mangas: [Manga]
    @Environment(WatchDependencies.self) private var dependencies

    var body: some View {
        // Filtered in memory: the watch keeps 50 mangas at most.
        let readingMangas = mangas.filter(\.isReading)
        List(readingMangas) { manga in
            NavigationLink(value: manga) {
                WatchMangaRowView(manga: manga)
            }
        }
        .navigationDestination(for: Manga.self) { manga in
            WatchMangaDetailView(manga: manga, dependencies: dependencies)
        }
        .overlay {
            if readingMangas.isEmpty {
                WatchSignedOutView(isSynced: true)
            }
        }
        .navigationTitle("Reading")
    }
}

#Preview("Reading list", traits: .sampleData) {
    WatchReadingListView()
}

#Preview("Nothing in progress", traits: .emptyStore) {
    WatchReadingListView()
}
