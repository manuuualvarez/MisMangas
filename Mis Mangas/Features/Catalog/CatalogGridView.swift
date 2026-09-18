//
//  CatalogGridView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// The covers of one catalog mode in an adaptive grid (three columns on iPhone), read from the
/// store in server order. Tapping a cell selects its manga; the owner presents the selection.
/// Same states and paging as the list. The column width scales with the text size, so larger
/// text gets fewer, wider columns instead of squeezed cells.
struct CatalogGridView: View {
    @Query private var entries: [CatalogEntry]
    @Binding var selection: Manga?
    @Bindable var viewModel: CatalogViewModel
    let namespace: Namespace.ID

    @ScaledMetric(relativeTo: .subheadline) private var minimumColumnWidth: CGFloat = 110

    init(modeKey: String, selection: Binding<Manga?>, viewModel: CatalogViewModel, namespace: Namespace.ID) {
        _entries = Query(filter: #Predicate<CatalogEntry> { $0.modeKey == modeKey }, sort: \.ordinal)
        _selection = selection
        self.viewModel = viewModel
        self.namespace = namespace
    }

    var body: some View {
        ScrollView {
            if entries.isEmpty {
                CatalogPlaceholderView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: 12)], alignment: .leading, spacing: 16) {
                    ForEach(entries) { entry in
                        if let manga = entry.manga {
                            Button {
                                selection = manga
                            } label: {
                                CatalogGridCellView(manga: manga, namespace: namespace, isSelected: selection == manga)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if entry === entries.last {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                if let error = viewModel.loadError {
                    InlineErrorView(error: error) {
                        Task { await viewModel.retry() }
                    }
                    .padding(.horizontal)
                }
                PaginationFooterView(
                    isLoading: viewModel.isLoading,
                    hasNextPage: viewModel.hasNextPage,
                    page: viewModel.currentPage + 1,
                    totalPages: viewModel.totalPages
                )
            }
        }
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

#Preview("Grid", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @Namespace var namespace
    @Previewable @State var selection: Manga?
    NavigationStack {
        CatalogGridView(
            modeKey: "all",
            selection: $selection,
            viewModel: CatalogViewModel(syncService: dependencies.syncService),
            namespace: namespace
        )
    }
}
