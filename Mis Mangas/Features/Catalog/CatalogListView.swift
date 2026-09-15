//
//  CatalogListView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// The rows of one catalog mode, read from the store in server order. With nothing stored it
/// shows the loading, error or empty state inside the same list; with rows it keeps them visible
/// through errors and asks for the next page when the last row appears.
struct CatalogListView: View {
    @Query private var entries: [CatalogEntry]
    @Bindable var viewModel: CatalogViewModel
    let namespace: Namespace.ID

    init(modeKey: String, viewModel: CatalogViewModel, namespace: Namespace.ID) {
        _entries = Query(filter: #Predicate<CatalogEntry> { $0.modeKey == modeKey }, sort: \.ordinal)
        self.viewModel = viewModel
        self.namespace = namespace
    }

    var body: some View {
        List {
            if entries.isEmpty {
                placeholder
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    if let manga = entry.manga {
                        NavigationLink(value: manga) {
                            MangaCardView(manga: manga, namespace: namespace)
                        }
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
    }

    /// What the screen shows while the mode has no rows: the first load, its failure, or an
    /// empty server answer. Lives inside the list so the bars lay out against a scroll view.
    @ViewBuilder
    private var placeholder: some View {
        if viewModel.isLoading {
            ProgressView("Loading catalog…")
        } else if let error = viewModel.loadError {
            ErrorStateView(error: error) {
                Task { await viewModel.refresh() }
            }
        } else {
            EmptyStateView(title: "No mangas yet", systemImage: "books.vertical")
        }
    }
}

#Preview("List", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @Namespace var namespace
    NavigationStack {
        CatalogListView(modeKey: "all", viewModel: CatalogViewModel(syncService: dependencies.syncService), namespace: namespace)
    }
}
