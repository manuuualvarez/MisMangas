//
//  CatalogFiltersView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftUI

/// The filter form of the catalog: a picker per category fed by the server's lists, edited on a
/// draft and applied to the catalog on "Apply" through the same action the detail's chips use.
/// Presented as a sheet with its own navigation bar: title, Close and Apply.
struct CatalogFiltersView: View {
    /// The mode the catalog shows now: what the draft opens on and what "Apply" replaces.
    let mode: CatalogMode
    @Bindable var viewModel: CatalogViewModel
    @State private var draft: CatalogFilterDraft
    @Environment(\.applyCatalogMode) private var applyCatalogMode
    @Environment(\.dismiss) private var dismiss

    init(mode: CatalogMode, viewModel: CatalogViewModel) {
        self.mode = mode
        self.viewModel = viewModel
        _draft = State(initialValue: CatalogFilterDraft(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                CatalogFilterPickerView(
                    title: "Genre",
                    unavailableTitle: "Couldn't load genres",
                    options: viewModel.taxonomies?.genres,
                    error: viewModel.taxonomyError,
                    selection: $draft.genre
                ) {
                    Task { await viewModel.loadTaxonomies() }
                }
                CatalogFilterPickerView(
                    title: "Theme",
                    unavailableTitle: "Couldn't load themes",
                    options: viewModel.taxonomies?.themes,
                    error: viewModel.taxonomyError,
                    selection: $draft.theme
                ) {
                    Task { await viewModel.loadTaxonomies() }
                }
                CatalogFilterPickerView(
                    title: "Demographic",
                    unavailableTitle: "Couldn't load demographics",
                    options: viewModel.taxonomies?.demographics,
                    error: viewModel.taxonomyError,
                    selection: $draft.demographic
                ) {
                    Task { await viewModel.loadTaxonomies() }
                }
                Section {
                    Button("Clear filter", role: .destructive) {
                        applyCatalogMode?.apply(.all)
                        dismiss()
                    }
                    .disabled(!mode.isFiltered)
                    // The system red falls below 4.5:1 on a light row.
                    .foregroundStyle(.mmDestructive)
                } footer: {
                    Text("One category at a time: choosing a genre, theme or demographic sets the other two to Any.")
                        .foregroundStyle(.mmSecondaryLabel)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Symbols, not words: the text stays as the accessible name of each button.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", systemImage: "checkmark") {
                        applyCatalogMode?.apply(draft.applied(to: mode))
                        dismiss()
                    }
                    // The confirming button is filled: the fill accent keeps its symbol legible.
                    .tint(.mmAccentFill)
                }
            }
        }
        // The form outlives its presentations: a mode applied elsewhere (menu, chip) resets the draft.
        .onChange(of: mode) { _, mode in
            draft = CatalogFilterDraft(mode: mode)
        }
        .task {
            await viewModel.loadTaxonomies()
        }
    }
}

#Preview("Loaded", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogFiltersView(mode: .byGenre("Romance"), viewModel: CatalogViewModel(syncService: dependencies.syncService))
}

#Preview("Themes failed", traits: .sampleData(catalog: .sample, themes: .failure(.serverError))) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogFiltersView(mode: .all, viewModel: CatalogViewModel(syncService: dependencies.syncService))
}

#Preview("No network", traits: .emptyStore(catalog: .failure(.serverError))) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogFiltersView(mode: .all, viewModel: CatalogViewModel(syncService: dependencies.syncService))
}
