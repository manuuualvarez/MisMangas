//
//  CatalogView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// The catalog screen: the mode as title with the server total, the All / Best picker while no
/// filter is active, and the mangas of the mode as a grid (default) or a list, chosen from the
/// toolbar menu and remembered. The same menu opens the filter form, an inspector the system
/// shows as a trailing column or a sheet. A two-column split view: the catalog leads and the
/// selected manga fills the detail column on iPad; on iPhone the columns collapse into one
/// stack and the detail is pushed. A chip in the detail applies its category here: the detail
/// closes and the mode changes. Each mode change rebuilds the content so its query follows it.
struct CatalogView: View {
    @State private var viewModel: CatalogViewModel
    @State private var selectedMode: CatalogMode
    @State private var selectedManga: Manga?
    @State private var isPresentingFilters = false
    @AppStorage("catalog.displayMode") private var displayMode: DisplayMode = .grid
    @Namespace private var heroNamespace

    init(syncService: MangaSyncService, mode: CatalogMode = .all) {
        _viewModel = State(initialValue: CatalogViewModel(syncService: syncService, mode: mode))
        _selectedMode = State(initialValue: mode)
    }

    var body: some View {
        NavigationSplitView {
            Group {
                switch displayMode {
                case .grid:
                    CatalogGridView(
                        modeKey: selectedMode.modeKey,
                        selection: $selectedManga,
                        viewModel: viewModel,
                        namespace: heroNamespace
                    )
                case .list:
                    CatalogListView(
                        modeKey: selectedMode.modeKey,
                        selection: $selectedManga,
                        viewModel: viewModel,
                        namespace: heroNamespace
                    )
                }
            }
            .safeAreaBar(edge: .top) {
                if !selectedMode.isFiltered {
                    CatalogModePickerView(selection: $selectedMode)
                }
            }
            .navigationTitle(selectedMode.title)
            .navigationSubtitle(.catalogTotal(viewModel.totalCount, isFailed: viewModel.loadError != nil))
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Layout", selection: $displayMode) {
                            Label("Grid", systemImage: DisplayMode.grid.systemImage).tag(DisplayMode.grid)
                            Label("List", systemImage: DisplayMode.list.systemImage).tag(DisplayMode.list)
                        }
                        Toggle("Filters", systemImage: "line.3.horizontal.decrease", isOn: $isPresentingFilters)
                        if selectedMode.isFiltered {
                            Button("Clear filter", systemImage: "xmark.circle") {
                                modeApplier.apply(.all)
                            }
                        }
                    } label: {
                        Label("Options", systemImage: displayMode.systemImage)
                    }
                    .accessibilityValue(Text(displayMode.title))
                    .accessibilityHint("Changes the layout, opens the filters or clears the filter")
                }
            }
            .navigationDestination(item: $selectedManga) { manga in
                MangaDetailView(manga: manga)
                    .navigationTransition(.zoom(sourceID: manga.id, in: heroNamespace))
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 520, max: 720)
            .task(id: selectedMode) {
                await viewModel.loadInitial(mode: selectedMode)
            }
            .refreshable {
                await viewModel.refresh()
            }
        } detail: {
            ContentUnavailableView("Select a manga", systemImage: "book.closed")
        }
        .navigationSplitViewStyle(.balanced)
        // The split view changes identity with the mode: the content's query follows the mode
        // and the navigation bar comes back expanded over the new content, as it does after a
        // detail is popped. Replacing only the column content left the bar collapsed. The
        // inspector sits outside that identity, so its presentation survives the change.
        .id(selectedMode)
        .inspector(isPresented: $isPresentingFilters) {
            CatalogFiltersView(mode: selectedMode, viewModel: viewModel)
        }
        .environment(\.applyCatalogMode, modeApplier)
        // Outside the identity change, or a fresh split view would never see the mode change.
        // A chip in the detail column changes the catalog's title while focus is elsewhere.
        .onChange(of: selectedMode) { _, mode in
            AccessibilityNotification.Announcement(String(localized: "Showing \(mode.title)")).post()
        }
    }

    /// Every way of changing the mode goes through here: the filter form, the chips of a detail
    /// and the menu. A mode change always closes the detail.
    private var modeApplier: SelectedModeApplier {
        SelectedModeApplier(mode: $selectedMode, selectedManga: $selectedManga)
    }
}

#Preview("Catalog", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogView(syncService: dependencies.syncService)
}

#Preview("Filtered", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogView(syncService: dependencies.syncService, mode: .byGenre("Romance"))
}

#Preview("Error with data", traits: .sampleData(catalog: .failure(.serverError))) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogView(syncService: dependencies.syncService)
}

#Preview("Empty", traits: .emptyStore()) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogView(syncService: dependencies.syncService)
}

#Preview("Error", traits: .emptyStore(catalog: .failure(.serverError))) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogView(syncService: dependencies.syncService)
}
