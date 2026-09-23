//
//  AuthorPickerView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

/// The authors that match the field, one row each with their credit ("Akira Toriyama · Story &
/// Art"). Rows, not a list: the suggestions container already lists them. Tapping one ends the
/// search and shows the author's works as the results. While a request is in flight the previous
/// rows stay; nothing found says so, and a failure offers a retry.
struct AuthorPickerView: View {
    @Bindable var viewModel: CatalogViewModel
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        if let error = viewModel.searchError {
            InlineErrorView(error: error) {
                viewModel.searchAuthors(viewModel.searchText)
            }
        } else if !viewModel.authorResults.isEmpty {
            ForEach(viewModel.authorResults) { author in
                Button {
                    dismissSearch()
                    Task { await viewModel.select(author: author) }
                } label: {
                    LabeledContent(author.displayName, value: author.role.displayName)
                }
                .accessibilityLabel(String(localized: "\(author.displayName), \(author.role.displayName)"))
                .accessibilityHint("Shows mangas by this author")
            }
        } else if viewModel.isSearchingAuthors {
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Searching authors")
        } else if viewModel.hasAuthorQuery {
            ContentUnavailableView.search(text: viewModel.authorQuery)
        }
    }
}

#Preview("Results", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var viewModel: CatalogViewModel?
    List {
        if let viewModel {
            AuthorPickerView(viewModel: viewModel)
        }
    }
    .task {
        let model = CatalogViewModel(syncService: dependencies.syncService)
        model.searchAuthors("tori")
        viewModel = model
    }
}

#Preview("Error", traits: .sampleData(catalog: .failure(.serverError))) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var viewModel: CatalogViewModel?
    List {
        if let viewModel {
            AuthorPickerView(viewModel: viewModel)
        }
    }
    .task {
        let model = CatalogViewModel(syncService: dependencies.syncService)
        model.searchAuthors("tori")
        viewModel = model
    }
}

#Preview("No results", traits: .sampleData(catalog: .empty)) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var viewModel: CatalogViewModel?
    List {
        if let viewModel {
            AuthorPickerView(viewModel: viewModel)
        }
    }
    .task {
        let model = CatalogViewModel(syncService: dependencies.syncService)
        model.searchAuthors("zzz")
        viewModel = model
    }
}
