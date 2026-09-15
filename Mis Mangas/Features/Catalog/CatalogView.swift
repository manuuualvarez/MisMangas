//
//  CatalogView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// The catalog screen: title with the server total, All / Best picker, and the mangas of the
/// selected mode as a grid (default) or a list, chosen from the toolbar menu and remembered.
/// Each mode change rebuilds the content so its query follows the mode.
struct CatalogView: View {
    @State private var viewModel: CatalogViewModel
    @State private var selectedMode: CatalogMode = .all
    @AppStorage("catalog.displayMode") private var displayMode: DisplayMode = .grid
    @Namespace private var heroNamespace

    init(syncService: MangaSyncService) {
        _viewModel = State(initialValue: CatalogViewModel(syncService: syncService))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch displayMode {
                case .grid:
                    CatalogGridView(modeKey: selectedMode.modeKey, viewModel: viewModel, namespace: heroNamespace)
                case .list:
                    CatalogListView(modeKey: selectedMode.modeKey, viewModel: viewModel, namespace: heroNamespace)
                }
            }
            .id(selectedMode)
            .safeAreaBar(edge: .top) {
                CatalogModePickerView(selection: $selectedMode)
            }
            .navigationTitle("Catalog")
            .navigationSubtitle(subtitle)
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
            .navigationDestination(for: Manga.self) { manga in
                // Placeholder until the detail screen exists.
                Text(manga.title)
                    .navigationTitle(manga.title)
            }
            .task(id: selectedMode) {
                await viewModel.loadInitial(mode: selectedMode)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
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
