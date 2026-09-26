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
        // The list owns the selection and the split view's detail column follows it: that is
        // what draws the platform's own highlight on the selected row.
        List(selection: $selection) {
            if entries.isEmpty {
                // Inside the list so the bars lay out against a scroll view.
                CatalogPlaceholderView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    if let manga = entry.manga {
                        MangaCardView(manga: manga, namespace: namespace)
                            .tag(manga)
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
        // The selected row is a fill under white text: the fill accent, not the text one.
        .tint(.mmAccentFill)
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
