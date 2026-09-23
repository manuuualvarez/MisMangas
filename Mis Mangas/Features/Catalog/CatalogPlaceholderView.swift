//
//  CatalogPlaceholderView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

/// What the grid and the list show while their mode has no rows: the first load, its failure or
/// an empty answer. A filtered mode with nothing behind it reads as "no results", named after
/// what was asked, and so does a category the server does not know: asking again would not
/// change either. The two catalog listings keep their refresh button.
struct CatalogPlaceholderView: View {
    @Bindable var viewModel: CatalogViewModel

    var body: some View {
        if viewModel.isLoading {
            ProgressView("Loading catalog…")
        } else if let error = viewModel.loadError, !viewModel.isModeNotFound {
            ErrorStateView(error: error) {
                Task { await viewModel.refresh() }
            }
        } else {
            switch viewModel.currentMode {
            case .all, .best:
                EmptyStateView(title: "No mangas yet", systemImage: "books.vertical") {
                    Task { await viewModel.refresh() }
                }
            case let .titleContains(query), let .beginsWith(query):
                ContentUnavailableView.search(text: query)
            case .byGenre, .byTheme, .byDemographic, .byAuthor, .search:
                ContentUnavailableView(
                    "No mangas",
                    systemImage: "books.vertical",
                    description: Text("Nothing listed for \(viewModel.currentMode.title).")
                )
            }
        }
    }
}

#Preview("No results for a title", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogPlaceholderView(viewModel: CatalogViewModel(syncService: dependencies.syncService, mode: .titleContains("ball")))
}

#Preview("No mangas in a category", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogPlaceholderView(viewModel: CatalogViewModel(syncService: dependencies.syncService, mode: .byGenre("Romance")))
}

#Preview("Unknown category", traits: .sampleData(catalog: .failure(.notFound))) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var viewModel: CatalogViewModel?
    if let viewModel {
        CatalogPlaceholderView(viewModel: viewModel)
    } else {
        ProgressView()
            .task {
                let model = CatalogViewModel(syncService: dependencies.syncService, mode: .byGenre("zzz"))
                await model.refresh()
                viewModel = model
            }
    }
}

#Preview("Empty catalog", traits: .emptyStore()) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogPlaceholderView(viewModel: CatalogViewModel(syncService: dependencies.syncService))
}
