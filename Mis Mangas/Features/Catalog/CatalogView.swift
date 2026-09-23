//
//  CatalogView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// The catalog screen: the mode as title with the server total, the All / Best picker while no
/// filter is active, and the mangas of the mode as a grid (default) or a list, chosen from the
/// toolbar menu and remembered. The same menu opens the filter form as a sheet. A two-column
/// split view: the catalog leads and the selected manga fills the detail column on iPad; on
/// iPhone the columns collapse into one
/// stack and the detail is pushed. A chip in the detail applies its category here: the detail
/// closes and the mode changes. Each mode change rebuilds the content so its query follows it.
struct CatalogView: View {
    @State private var viewModel: CatalogViewModel
    @State private var selectedMode: CatalogMode
    @State private var selectedManga: Manga?
    /// Which column shows when the split view collapses into one: a grid cell selects with a
    /// button, and only a list selection makes the collapsed split view push the detail on
    /// its own.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var isPresentingFilters = false
    @AppStorage("catalog.displayMode") private var displayMode: DisplayMode = .grid
    @Namespace private var heroNamespace

    init(syncService: MangaSyncService, mode: CatalogMode = .all) {
        _viewModel = State(initialValue: CatalogViewModel(syncService: syncService, mode: mode))
        _selectedMode = State(initialValue: mode)
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
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
            // The first column of a split view is dressed as a sidebar, and this one is content:
            // the tab bar already is the app's sidebar. Content reads on the plain background.
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
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
                        Button("Filters…", systemImage: "line.3.horizontal.decrease") {
                            isPresentingFilters = true
                        }
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
            .navigationSplitViewColumnWidth(min: 380, ideal: 520, max: 720)
            // The view model decides whether this mode still needs loading.
            .task(id: selectedMode) {
                await viewModel.loadInitialIfNeeded(mode: selectedMode)
            }
            .refreshable {
                await viewModel.refresh()
            }
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
        // The split view changes identity with the mode: the content's query follows the mode
        // and the navigation bar comes back expanded over the new content, as it does after a
        // detail is popped. Replacing only the column content left the bar collapsed. The
        // sheet sits outside that identity, so its presentation survives the change.
        .id(selectedMode)
        // A sheet, not an inspector: a form that is filled, applied and closed is a modal in
        // every Apple app, and the inspector left its presentation out of sync with the control
        // that opens it when it was dismissed by dragging.
        .sheet(isPresented: $isPresentingFilters) {
            CatalogFiltersView(mode: selectedMode, viewModel: viewModel)
        }
        .environment(\.applyCatalogMode, modeApplier)
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
        // Outside the identity change, or a fresh split view would never see the mode change.
        // A chip in the detail column changes the catalog's title while focus is elsewhere.
        .onChange(of: selectedMode) { _, mode in
            // The All / Best picker writes the mode straight into the selection, so closing the
            // detail belongs here: whoever changes the mode, the open manga is no longer in the
            // list behind it.
            selectedManga = nil
            AccessibilityNotification.Announcement(String(localized: "Showing \(mode.title)")).post()
        }
    }

    /// How the filter form, the chips of a detail and the menu apply a mode here. Closing the
    /// detail belongs to the change of mode, above; this one also closes it when the mode applied
    /// is the one already shown, which changes nothing and would leave the manga on screen.
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
