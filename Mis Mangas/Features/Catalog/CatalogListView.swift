//
//  CatalogListView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// The rows of one catalog mode, read from the store in server order. Tapping a row selects
/// its manga; the owner presents the selection. With nothing stored it shows the loading,
/// error or empty state inside the same list; with rows it keeps them visible through errors
/// and asks for the next page when the last row appears.
struct CatalogListView: View {
    @Query private var entries: [CatalogEntry]
    @Binding var selection: Manga?
    @Bindable var viewModel: CatalogViewModel
    let namespace: Namespace.ID

    init(modeKey: String, selection: Binding<Manga?>, viewModel: CatalogViewModel, namespace: Namespace.ID) {
        _entries = Query(filter: #Predicate<CatalogEntry> { $0.modeKey == modeKey }, sort: \.ordinal)
        _selection = selection
        self.viewModel = viewModel
        self.namespace = namespace
    }

    var body: some View {
        List {
            if entries.isEmpty {
                // Inside the list so the bars lay out against a scroll view.
                CatalogPlaceholderView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    if let manga = entry.manga {
                        // A button, not a selectable row: a collapsed split view takes a
                        // sidebar selection as "show the detail column" and pushed its
                        // placeholder instead of the manga. Writing the selection from the
                        // button leaves the destination in charge, as the grid already did.
                        Button {
                            selection = manga
                        } label: {
                            MangaCardView(manga: manga, namespace: namespace)
                                // The whole row answers the tap, not only the text and the
                                // cover: a wide row leaves empty space on its trailing side.
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        // `nil` keeps the list's own row background for every other row.
                        .listRowBackground(selection == manga ? Color.mmSurface : nil)
                        .accessibilityAddTraits(selection == manga ? .isSelected : [])
                        .listRowSeparator(entry === entries.first ? .hidden : .visible, edges: .top)
                        .onAppear {
                            if entry === entries.last {
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                }
                if let error = viewModel.loadError {
                    InlineErrorView(error: error) {
                        Task { await viewModel.retry() }
                    }
                    .listRowSeparator(.hidden)
                }
                PaginationFooterView(
                    isLoading: viewModel.isLoading,
                    hasNextPage: viewModel.hasNextPage,
                    page: viewModel.currentPage + 1,
                    totalPages: viewModel.totalPages
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        // With rows on screen the failure lands below the fold without taking focus: tell
        // assistive technologies about it (with no rows the full-screen error state already does).
        // The error carries an `any Error`, so the message is what gets observed.
        .onChange(of: viewModel.loadError?.errorDescription) { _, description in
            if let description, !entries.isEmpty {
                AccessibilityNotification.Announcement(description).post()
            }
        }
    }
}

#Preview("List", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @Namespace var namespace
    @Previewable @State var selection: Manga?
    NavigationStack {
        CatalogListView(
            modeKey: "all",
            selection: $selection,
            viewModel: CatalogViewModel(syncService: dependencies.syncService),
            namespace: namespace
        )
    }
}

// The row of the manga shown in the detail column, as iPad keeps it while the detail is open.
#Preview("Selected row", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @Namespace var namespace
    @Previewable @Query var mangas: [Manga]
    @Previewable @State var selection: Manga?
    NavigationStack {
        CatalogListView(
            modeKey: "all",
            selection: $selection,
            viewModel: CatalogViewModel(syncService: dependencies.syncService),
            namespace: namespace
        )
    }
    .onAppear {
        selection = mangas.first
    }
}
