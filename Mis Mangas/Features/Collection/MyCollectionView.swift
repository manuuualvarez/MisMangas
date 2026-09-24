//
//  MyCollectionView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// The My Collection tab: every manga in the collection, read from the store, with a summary,
/// a filter (All / Reading / Complete), an order and a list or grid layout chosen from the
/// toolbar menu. A two-column split view like the catalog: the selected manga fills the detail
/// column on iPad and is pushed on iPhone. An empty collection offers a way to the catalog, and
/// a chip in the detail applies its category there.
struct MyCollectionView: View {
    @Query(filter: #Predicate<Manga> { $0.inCollection == true }, sort: \Manga.title)
    private var mangas: [Manga]
    @Binding var selectedTab: AppTab
    @Binding var pendingCatalogMode: CatalogMode?
    @State private var viewModel: CollectionViewModel
    @State private var filter: CollectionFilter
    @State private var sort = CollectionSort.title
    @State private var selectedManga: Manga?
    /// Which column shows when the split view collapses into one: a grid cell selects with a
    /// button, and only a list selection makes the collapsed split view push the detail on
    /// its own.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @AppStorage("collection.displayMode") private var displayMode: DisplayMode = .list
    @Namespace private var heroNamespace

    init(
        syncService: MangaSyncService,
        selectedTab: Binding<AppTab>,
        pendingCatalogMode: Binding<CatalogMode?>,
        filter: CollectionFilter = .all
    ) {
        _selectedTab = selectedTab
        _pendingCatalogMode = pendingCatalogMode
        _viewModel = State(initialValue: CollectionViewModel(syncService: syncService))
        _filter = State(initialValue: filter)
    }

    var body: some View {
        // Filtered and sorted in memory: a collection holds hundreds of series at most, well
        // within what one pass per update handles.
        let visibleMangas = mangas.filtered(by: filter).sorted(by: sort)
        // The summary counts the whole collection, whatever the filter shows.
        let stats = CollectionStats(mangas: mangas)
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            Group {
                if mangas.isEmpty {
                    ContentUnavailableView {
                        Label("Your collection is empty", systemImage: "books.vertical")
                    } description: {
                        Text("Add a manga from its page in the catalog.")
                    } actions: {
                        Button("Browse catalog") {
                            selectedTab = .catalog
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if visibleMangas.isEmpty {
                    ContentUnavailableView {
                        Label("No mangas match", systemImage: "line.3.horizontal.decrease")
                    } description: {
                        Text("No manga in your collection matches this filter.")
                    } actions: {
                        Button("Show all") {
                            filter = .all
                        }
                    }
                } else {
                    switch displayMode {
                    case .list:
                        CollectionListView(
                            mangas: visibleMangas,
                            stats: stats,
                            selection: $selectedManga,
                            viewModel: viewModel,
                            namespace: heroNamespace
                        )
                    case .grid:
                        CollectionGridView(
                            mangas: visibleMangas,
                            stats: stats,
                            selection: $selectedManga,
                            namespace: heroNamespace
                        )
                    }
                }
            }
            // Content, not a sidebar: the tab bar already is the app's sidebar.
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle("My Collection")
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(CollectionFilter.allCases, id: \.self) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        Picker("Sort by", selection: $sort) {
                            ForEach(CollectionSort.allCases, id: \.self) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                        Picker("Layout", selection: $displayMode) {
                            Label("Grid", systemImage: DisplayMode.grid.systemImage).tag(DisplayMode.grid)
                            Label("List", systemImage: DisplayMode.list.systemImage).tag(DisplayMode.list)
                        }
                    } label: {
                        Label("Options", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityValue(Text("\(filter.title), sorted by \(sort.title), \(displayMode.title)"))
                    .accessibilityHint("Filters, sorts or changes the layout of the collection")
                }
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 520, max: 720)
        } detail: {
            if let selectedManga {
                MangaDetailView(manga: selectedManga)
                    .navigationTransition(.zoom(sourceID: selectedManga.id, in: heroNamespace))
            } else {
                ContentUnavailableView("Select a manga", systemImage: "book.closed")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(
            \.applyCatalogMode,
            CollectionModeApplier(
                selectedTab: $selectedTab,
                pendingCatalogMode: $pendingCatalogMode,
                selectedManga: $selectedManga
            )
        )
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
    }
}

#Preview("Collection", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var selectedTab = AppTab.collection
    @Previewable @State var pendingMode: CatalogMode?
    MyCollectionView(syncService: dependencies.syncService, selectedTab: $selectedTab, pendingCatalogMode: $pendingMode)
}

#Preview("Reading", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var selectedTab = AppTab.collection
    @Previewable @State var pendingMode: CatalogMode?
    MyCollectionView(syncService: dependencies.syncService, selectedTab: $selectedTab, pendingCatalogMode: $pendingMode, filter: .reading)
}

#Preview("Empty", traits: .emptyStore()) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    @Previewable @State var selectedTab = AppTab.collection
    @Previewable @State var pendingMode: CatalogMode?
    MyCollectionView(syncService: dependencies.syncService, selectedTab: $selectedTab, pendingCatalogMode: $pendingMode)
}
