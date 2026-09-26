//
//  CollectionListView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// My Collection as rows under the summary. The list owns the selection, which the split view's
/// detail column follows. Swiping a row offers "Remove", which asks for confirmation like the
/// editor does; the outcome is announced, and a failure shows inline with a retry.
struct CollectionListView: View {
    let mangas: [Manga]
    let stats: CollectionStats
    @Binding var selection: Manga?
    @Bindable var viewModel: CollectionViewModel
    let namespace: Namespace.ID

    @State private var mangaPendingRemoval: Manga?
    @State private var isConfirmingRemoval = false

    var body: some View {
        List(selection: $selection) {
            CollectionStatsCard(stats: stats)
                .listRowSeparator(.hidden)
            ForEach(mangas) { manga in
                CollectionRowView(manga: manga, namespace: namespace, isSelected: selection == manga)
                    .tag(manga)
                    // No full swipe: removing takes a confirmation, as it does in the editor.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            mangaPendingRemoval = manga
                            isConfirmingRemoval = true
                        }
                    }
            }
            if let error = viewModel.error, viewModel.failedRemovalID != nil {
                InlineErrorView(error: error) {
                    Task {
                        await viewModel.retryRemoval()
                        announceRemoval(of: nil)
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        // An alert, centered: a confirmation dialog from the list becomes a popover on iPad that
        // points at the list, over the detail of another manga, and one presented from the row
        // itself never appears after the swipe and leaves the list out of step with its rows.
        .alert(
            "Remove from collection?",
            isPresented: $isConfirmingRemoval,
            presenting: mangaPendingRemoval
        ) { manga in
            Button("Remove", role: .destructive) {
                remove(manga)
            }
            Button("Cancel", role: .cancel) {}
        } message: { manga in
            Text("\(manga.title) and its volumes will leave your collection.")
        }
    }

    /// Closes the detail of a manga that leaves the collection, then removes it.
    private func remove(_ manga: Manga) {
        if selection == manga {
            selection = nil
        }
        let mangaID = manga.id
        let title = manga.title
        Task {
            await viewModel.remove(mangaID: mangaID)
            announceRemoval(of: title)
        }
    }

    /// Tells assistive technologies how a removal ended: the row disappears or an error appears
    /// below the rows, and neither takes focus.
    private func announceRemoval(of title: String?) {
        if let description = viewModel.error?.errorDescription {
            AccessibilityNotification.Announcement(description).post()
        } else if let title {
            AccessibilityNotification.Announcement(String(localized: "\(title) removed from collection")).post()
        }
    }
}

#Preview("List", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @Query(filter: #Predicate<Manga> { $0.inCollection == true }, sort: \Manga.title) var mangas: [Manga]
    @Previewable @State var selection: Manga?
    @Previewable @Namespace var namespace
    CollectionListView(
        mangas: mangas,
        stats: CollectionStats(mangas: mangas),
        selection: $selection,
        viewModel: dependencies.makeCollectionViewModel(presentsRejections: true),
        namespace: namespace
    )
}
