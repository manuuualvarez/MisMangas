//
//  SearchView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import Accessibility
import SwiftUI

/// The search tab: one field for titles and authors, told apart by a scope. Titles suggest while
/// typing and list their results on submit; authors list their matches and, once one is chosen,
/// that author's works. The results are a mode of this screen's own view model, shown with the
/// same grid and list as the catalog in the same two-column split. A chip or an author tapped in
/// a detail opened from here becomes the results of this screen.
struct SearchView: View {
    @State private var viewModel: CatalogViewModel
    @State private var selectedManga: Manga?
    /// Which column shows when the split view collapses into one: a grid cell selects with a
    /// button, and only a list selection makes the collapsed split view push the detail on
    /// its own.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var isPresentingAdvancedSearch = false
    @AppStorage("catalog.displayMode") private var displayMode: DisplayMode = .grid
    @Namespace private var heroNamespace

    init(syncService: MangaSyncService) {
        _viewModel = State(initialValue: CatalogViewModel(syncService: syncService))
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
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
            // The first column of a split view is dressed as a sidebar, and this one is content:
            // the tab bar already is the app's sidebar. Content reads on the plain background.
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // The icon shows the layout in use, as the catalog's menu does: the same
                    // picture must not mean "you are on the grid" in one tab and "go to the
                    // grid" in the other.
                    Button(displayMode.toggled.title, systemImage: displayMode.systemImage) {
                        displayMode = displayMode.toggled
                    }
                    // Read as the control it is ("Layout, Grid") rather than as the layout it
                    // would switch to; nothing to lay out before the first results.
                    .accessibilityLabel("Layout")
                    .accessibilityValue(Text(displayMode.title))
                    .accessibilityHint(displayMode.toggled == .list ? "Shows the results as a list" : "Shows the results as a grid")
                    // Voice Control users name what they see: the icon shows the layout in use,
                    // the large content viewer the one it switches to, neither the accessible name.
                    .accessibilityInputLabels([Text("Layout"), Text(displayMode.title), Text(displayMode.toggled.title)])
                    .disabled(!viewModel.currentMode.isFiltered)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // A sheet returns the binding to false when it is dismissed, so the
                    // button only has to present it.
                    Button("Advanced search", systemImage: "slider.horizontal.3") {
                        isPresentingAdvancedSearch = true
                    }
                    .accessibilityHint("Searches by title, author and several categories at once")
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
            // A sheet, not an inspector: a form that is filled, applied and closed is a modal
            // in every Apple app, and in a compact width the inspector merged its navigation
            // bar into this screen's and took the search field's place as first responder.
            .sheet(isPresented: $isPresentingAdvancedSearch) {
                AdvancedSearchView(viewModel: viewModel)
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 520, max: 720)
        } detail: {
            // The detail column is the destination of the selection: in a regular width it is
            // the second column, and collapsed the split view pushes it on its own.
            if let selectedManga {
                MangaDetailView(manga: selectedManga)
                    .navigationTransition(.zoom(sourceID: selectedManga.id, in: heroNamespace))
            } else {
                ContentUnavailableView("Select a manga", systemImage: "book.closed")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.applyCatalogMode, SearchModeApplier(viewModel: viewModel, selectedManga: $selectedManga))
        // Collapsed, the detail shows whenever a manga is selected, whether a list row or a
        // grid cell selected it; going back deselects it, so the same cell opens it again.
        .onChange(of: selectedManga) { _, manga in
            compactColumn = manga == nil ? .sidebar : .detail
        }
        .onChange(of: compactColumn) { _, column in
            if column == .sidebar {
                selectedManga = nil
            }
        }
        // What lands under the field while focus stays in it is announced: results replacing
        // the content, suggestions, author matches and failures.
        .onChange(of: viewModel.currentMode) { _, mode in
            AccessibilityNotification.Announcement(String(localized: "Showing \(mode.title)")).post()
        }
        .onChange(of: viewModel.suggestionsKey) { _, key in
            if key != nil {
                // Low priority, because this fires once per debounce while the field is being
                // typed into: at the usual priority it cuts the echo of the very keys the
                // reader is pressing. Dropped when VoiceOver is already speaking.
                var announcement = AttributedString(localized: "Suggestions updated")
                announcement.accessibilitySpeechAnnouncementPriority = .low
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
        .onChange(of: viewModel.authorResults.count) { _, count in
            guard viewModel.searchScope == .authors, viewModel.hasAuthorQuery else {
                return
            }
            // Grammar agreement keeps a single match from being announced as "1 authors found".
            var message = count == 0
                ? AttributedString(localized: "No authors found")
                : AttributedString(localized: "^[\(count) author](inflect: true) found")
            // Same reason as the suggestions: these land while the field is being typed into.
            message.accessibilitySpeechAnnouncementPriority = .low
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
