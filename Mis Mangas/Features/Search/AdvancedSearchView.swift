//
//  AdvancedSearchView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 18/09/2026.
//

import SwiftUI

/// The advanced search form: a title, an author's name, any number of genres, themes and
/// demographics, and whether the texts must be contained or begin the value. It edits the fields
/// of the search tab's view model, so it reopens with whatever was left in it. Presented as a
/// sheet with its own navigation bar: title, Close and Search.
struct AdvancedSearchView: View {
    @Bindable var viewModel: CatalogViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Each field keeps a visible label: a placeholder is gone once the field is filled,
                // and the system one falls far below 4.5:1.
                Section {
                    LabeledContent("Title") {
                        TextField("Title", text: $viewModel.draftTitle, prompt: Text("Any").foregroundStyle(.mmSecondaryLabel))
                    }
                }
                Section {
                    LabeledContent("First name") {
                        TextField("First name", text: $viewModel.draftAuthorFirstName, prompt: Text("Any").foregroundStyle(.mmSecondaryLabel))
                    }
                    LabeledContent("Last name") {
                        TextField("Last name", text: $viewModel.draftAuthorLastName, prompt: Text("Any").foregroundStyle(.mmSecondaryLabel))
                    }
                } header: {
                    Text("Author")
                        .foregroundStyle(.mmSecondaryLabel)
                }
                TaxonomySectionView(
                    title: "Genres",
                    unavailableTitle: "Couldn't load genres",
                    expandHint: "Expands the genres",
                    collapseHint: "Collapses the genres",
                    options: viewModel.taxonomies?.genres,
                    error: viewModel.taxonomyError,
                    selection: $viewModel.draftGenres,
                    retry: retry
                )
                TaxonomySectionView(
                    title: "Themes",
                    unavailableTitle: "Couldn't load themes",
                    expandHint: "Expands the themes",
                    collapseHint: "Collapses the themes",
                    options: viewModel.taxonomies?.themes,
                    error: viewModel.taxonomyError,
                    selection: $viewModel.draftThemes,
                    retry: retry
                )
                TaxonomySectionView(
                    title: "Demographics",
                    unavailableTitle: "Couldn't load demographics",
                    expandHint: "Expands the demographics",
                    collapseHint: "Collapses the demographics",
                    options: viewModel.taxonomies?.demographics,
                    error: viewModel.taxonomyError,
                    selection: $viewModel.draftDemographics,
                    retry: retry
                )
                Section {
                    Toggle("Contains", isOn: $viewModel.draftContains)
                } footer: {
                    Text("On, the texts are searched anywhere in the value; off, only at its beginning.")
                        .foregroundStyle(.mmSecondaryLabel)
                }
                Section {
                    Button("Reset", role: .destructive) {
                        viewModel.resetDraft()
                    }
                    .disabled(viewModel.isDraftEmpty)
                    // The system red falls below 4.5:1 on a light row.
                    .foregroundStyle(.mmDestructive)
                }
            }
            .navigationTitle("Advanced search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Symbols, not words: the text stays as the accessible name of each button.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search", systemImage: "magnifyingglass") {
                        Task { await viewModel.applyAdvancedSearch() }
                        dismiss()
                    }
                    // The confirming button is filled: the fill accent keeps its symbol legible.
                    .tint(.mmAccentFill)
                }
            }
        }
        .task {
            await viewModel.loadTaxonomies()
        }
    }

    private func retry() {
        Task { await viewModel.loadTaxonomies() }
    }
}

#Preview("Empty", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    AdvancedSearchView(viewModel: CatalogViewModel(syncService: dependencies.syncService))
}

#Preview("Filled", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var viewModel: CatalogViewModel?
    Group {
        if let viewModel {
            AdvancedSearchView(viewModel: viewModel)
        }
    }
    .task {
        let model = CatalogViewModel(syncService: dependencies.syncService)
        await model.loadTaxonomies()
        model.draftTitle = "dragon"
        model.draftAuthorLastName = "Toriyama"
        model.draftGenres = ["Action", "Adventure"]
        model.draftContains = true
        viewModel = model
    }
}

#Preview("Themes failed", traits: .sampleData(catalog: .sample, themes: .failure(.serverError))) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    AdvancedSearchView(viewModel: CatalogViewModel(syncService: dependencies.syncService))
}
