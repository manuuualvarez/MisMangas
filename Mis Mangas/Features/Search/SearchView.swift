//
//  SearchView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

/// The search tab: one field for titles and authors, told apart by a scope. Titles suggest while
/// typing and list their results on submit; authors list their matches and, once one is chosen,
/// that author's works. The results are a mode of this screen's own view model, shown with the
/// same grid and list as the catalog in the same two-column split. A chip or an author tapped in
/// a detail opened from here becomes the results of this screen.
struct SearchView: View {
    @State private var viewModel: CatalogViewModel
    @State private var selectedManga: Manga?
    @AppStorage("catalog.displayMode") private var displayMode: DisplayMode = .grid
    @Namespace private var heroNamespace

    init(syncService: MangaSyncService) {
        _viewModel = State(initialValue: CatalogViewModel(syncService: syncService))
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if viewModel.currentMode.isFiltered {
                    switch displayMode {
                    case .grid:
                        CatalogGridView(
                            modeKey: viewModel.currentMode.modeKey,
                            selection: $selectedManga,
                            viewModel: viewModel,
                            namespace: heroNamespace
                        )
                    case .list:
                        CatalogListView(
                            modeKey: viewModel.currentMode.modeKey,
                            selection: $selectedManga,
                            viewModel: viewModel,
                            namespace: heroNamespace
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "Search the catalog",
                        systemImage: "magnifyingglass",
                        description: Text("Titles, or authors with the Authors scope.")
                    )
                }
            }
            // The grid and the list build their query when created: a new mode needs a new one.
            .id(viewModel.currentMode)
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(displayMode.toggled.title, systemImage: displayMode.toggled.systemImage) {
                        displayMode = displayMode.toggled
                    }
                    // Read as the control it is ("Layout, Grid") rather than as the layout it
                    // would switch to; nothing to lay out before the first results.
                    .accessibilityLabel("Layout")
                    .accessibilityValue(Text(displayMode.title))
                    .accessibilityHint(displayMode.toggled == .list ? "Shows the results as a list" : "Shows the results as a grid")
                    .disabled(!viewModel.currentMode.isFiltered)
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Titles or authors")
            // Scopes from the moment the field opens, so an author can be looked up without a
            // title search running first (by default they only show once text is typed).
            .searchScopes($viewModel.searchScope, activation: .onSearchPresentation) {
                Text("Titles").tag(SearchScope.titles)
                Text("Authors").tag(SearchScope.authors)
            }
            .searchSuggestions {
                switch viewModel.searchScope {
                case .titles:
                    if let error = viewModel.searchError {
                        InlineErrorView(error: error) {
                            viewModel.updateSearchText(viewModel.searchText)
                        }
                    } else if let key = viewModel.suggestionsKey {
                        SearchSuggestionsView(modeKey: key, selection: $selectedManga)
                            .id(key)
                    }
                case .authors:
                    AuthorPickerView(viewModel: viewModel)
                }
            }
            .onSubmit(of: .search) {
                Task { await viewModel.submitSearch() }
            }
            .onChange(of: viewModel.searchText) { _, text in
                viewModel.search(text)
            }
            // Text typed under one scope is searched again under the other.
            .onChange(of: viewModel.searchScope) { _, _ in
                viewModel.search(viewModel.searchText)
            }
            .navigationDestination(item: $selectedManga) { manga in
                MangaDetailView(manga: manga)
                    .navigationTransition(.zoom(sourceID: manga.id, in: heroNamespace))
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 520, max: 720)
        } detail: {
            ContentUnavailableView("Select a manga", systemImage: "book.closed")
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.applyCatalogMode, SearchModeApplier(viewModel: viewModel, selectedManga: $selectedManga))
        // What lands under the field while focus stays in it is announced: results replacing
        // the content, suggestions, author matches and failures.
        .onChange(of: viewModel.currentMode) { _, mode in
            AccessibilityNotification.Announcement(String(localized: "Showing \(mode.title)")).post()
        }
        .onChange(of: viewModel.suggestionsKey) { _, key in
            if key != nil {
                AccessibilityNotification.Announcement(String(localized: "Suggestions updated")).post()
            }
        }
        .onChange(of: viewModel.authorResults.count) { _, count in
            guard viewModel.searchScope == .authors, viewModel.hasAuthorQuery else {
                return
            }
            // One form per count: a single match must not be announced as "1 authors found".
            let message = switch count {
            case 0: String(localized: "No authors found")
            case 1: String(localized: "1 author found")
            default: String(localized: "\(count) authors found")
            }
            AccessibilityNotification.Announcement(message).post()
        }
        .onChange(of: viewModel.searchError?.errorDescription) { _, description in
            if let description {
                AccessibilityNotification.Announcement(description).post()
            }
        }
    }

    /// "Search" until the first results; then the mode names them ("Results for “ball”").
    private var title: String {
        viewModel.currentMode.isFiltered ? viewModel.currentMode.title : String(localized: "Search")
    }

    /// The results total, as in the catalog; nothing before the first search.
    private var subtitle: Text {
        viewModel.currentMode.isFiltered
            ? .catalogTotal(viewModel.totalCount, isFailed: viewModel.loadError != nil)
            : Text(verbatim: "")
    }
}

#Preview("Search", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    SearchView(syncService: dependencies.syncService)
}

#Preview("iPad", traits: .sampleData, .landscapeLeft) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    SearchView(syncService: dependencies.syncService)
}
