//
//  CatalogView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// The catalog screen: title with the server total, All / Best picker, and the mangas of the
/// selected mode as a grid (default) or a list, chosen from the toolbar menu and remembered.
/// A two-column split view: the catalog leads and the selected manga fills the detail column
/// on iPad; on iPhone the columns collapse into one stack and the detail is pushed.
/// Each mode change rebuilds the content so its query follows the mode.
struct CatalogView: View {
    @State private var viewModel: CatalogViewModel
    @State private var selectedMode: CatalogMode = .all
    @State private var selectedManga: Manga?
    @AppStorage("catalog.displayMode") private var displayMode: DisplayMode = .grid
    @Namespace private var heroNamespace

    init(syncService: MangaSyncService) {
        _viewModel = State(initialValue: CatalogViewModel(syncService: syncService))
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
            .id(selectedMode)
            .safeAreaBar(edge: .top) {
                CatalogModePickerView(selection: $selectedMode)
            }
            .navigationTitle("Catalog")
            .navigationSubtitle(subtitle)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Layout", selection: $displayMode) {
                            Label("Grid", systemImage: DisplayMode.grid.systemImage).tag(DisplayMode.grid)
                            Label("List", systemImage: DisplayMode.list.systemImage).tag(DisplayMode.list)
                        }
                    } label: {
                        Label("Layout", systemImage: displayMode.systemImage)
                    }
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
    }

    private var subtitle: Text {
        if let total = viewModel.totalCount {
            Text("\(total, format: .number) mangas")
        } else {
            Text(verbatim: "")
        }
    }
}

#Preview("Catalog", traits: .sampleData) {
    @Previewable @Environment(AppDependencies.self) var dependencies
    CatalogView(syncService: dependencies.syncService)
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
