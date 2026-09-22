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
    @State private var isShowingGenres = false
    @State private var isShowingThemes = false
    @State private var isShowingDemographics = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $viewModel.draftTitle)
                }
                Section("Author") {
                    // With both fields filled the placeholder is gone from the screen and the
                    // section header alone does not tell a first name from a last one.
                    TextField("First name", text: $viewModel.draftAuthorFirstName)
                        .accessibilityLabel("First name")
                    TextField("Last name", text: $viewModel.draftAuthorLastName)
                        .accessibilityLabel("Last name")
                }
                // Collapsed until asked for: the server lists 21 genres, 52 themes and 5
                // demographics, and expanded they bury everything below them.
                Section {
                    DisclosureGroup(isExpanded: $isShowingGenres) {
                        if let genres = viewModel.taxonomies?.genres {
                            if genres.isEmpty, let error = viewModel.taxonomyError {
                                Text("Couldn't load genres")
                                InlineErrorView(error: error) {
                                    Task { await viewModel.loadTaxonomies() }
                                }
                            } else {
                                MultiSelectChipsView(title: "Genres", options: genres, selection: $viewModel.draftGenres)
                            }
                        } else {
                            ProgressView()
                                .accessibilityLabel("Loading")
                        }
                    } label: {
                        // The count rides in the value, not in the name: read as part of the
                        // label a screen reader would say the middle dot out loud, and the hint
                        // is what tells whether tapping opens or closes the group.
                        if viewModel.draftGenres.isEmpty {
                            Text("Genres")
                                .accessibilityHint(isShowingGenres ? "Collapses the genres" : "Expands the genres")
                        } else {
                            Text("Genres · \(viewModel.draftGenres.count)")
                                .accessibilityLabel("Genres")
                                .accessibilityValue("\(viewModel.draftGenres.count) selected")
                                .accessibilityHint(isShowingGenres ? "Collapses the genres" : "Expands the genres")
                        }
                    }
                }
                Section {
                    DisclosureGroup(isExpanded: $isShowingThemes) {
                        if let themes = viewModel.taxonomies?.themes {
                            if themes.isEmpty, let error = viewModel.taxonomyError {
                                Text("Couldn't load themes")
                                InlineErrorView(error: error) {
                                    Task { await viewModel.loadTaxonomies() }
                                }
                            } else {
                                MultiSelectChipsView(title: "Themes", options: themes, selection: $viewModel.draftThemes)
                            }
                        } else {
                            ProgressView()
                                .accessibilityLabel("Loading")
                        }
                    } label: {
                        // The count rides in the value, not in the name: read as part of the
                        // label a screen reader would say the middle dot out loud, and the hint
                        // is what tells whether tapping opens or closes the group.
                        if viewModel.draftThemes.isEmpty {
                            Text("Themes")
                                .accessibilityHint(isShowingThemes ? "Collapses the themes" : "Expands the themes")
                        } else {
                            Text("Themes · \(viewModel.draftThemes.count)")
                                .accessibilityLabel("Themes")
                                .accessibilityValue("\(viewModel.draftThemes.count) selected")
                                .accessibilityHint(isShowingThemes ? "Collapses the themes" : "Expands the themes")
                        }
                    }
                }
                Section {
                    DisclosureGroup(isExpanded: $isShowingDemographics) {
                        if let demographics = viewModel.taxonomies?.demographics {
                            if demographics.isEmpty, let error = viewModel.taxonomyError {
                                Text("Couldn't load demographics")
                                InlineErrorView(error: error) {
                                    Task { await viewModel.loadTaxonomies() }
                                }
                            } else {
                                MultiSelectChipsView(title: "Demographics", options: demographics, selection: $viewModel.draftDemographics)
                            }
                        } else {
                            ProgressView()
                                .accessibilityLabel("Loading")
                        }
                    } label: {
                        // The count rides in the value, not in the name: read as part of the
                        // label a screen reader would say the middle dot out loud, and the hint
                        // is what tells whether tapping opens or closes the group.
                        if viewModel.draftDemographics.isEmpty {
                            Text("Demographics")
                                .accessibilityHint(isShowingDemographics ? "Collapses the demographics" : "Expands the demographics")
                        } else {
                            Text("Demographics · \(viewModel.draftDemographics.count)")
                                .accessibilityLabel("Demographics")
                                .accessibilityValue("\(viewModel.draftDemographics.count) selected")
                                .accessibilityHint(isShowingDemographics ? "Collapses the demographics" : "Expands the demographics")
                        }
                    }
                }
                Section {
                    Toggle("Contains", isOn: $viewModel.draftContains)
                } footer: {
                    Text("On, the texts are searched anywhere in the value; off, only at its beginning.")
                }
                Section {
                    Button("Reset", role: .destructive) {
                        viewModel.resetDraft()
                    }
                    .disabled(viewModel.isDraftEmpty)
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
                }
            }
        }
        .task {
            await viewModel.loadTaxonomies()
        }
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
