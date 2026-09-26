//
//  MainTabView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Top-level tabs: a tab bar on iPhone, a sidebar-adaptable bar on iPad. Search is the tab with
/// that role: the system draws it apart from the others and hosts its field. The selected tab is
/// state here so My Collection can send the user to the catalog, with a mode to apply there.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var selectedTab = AppTab.catalog
    @State private var pendingCatalogMode: CatalogMode?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Catalog", systemImage: "books.vertical", value: .catalog) {
                CatalogView(syncService: dependencies.syncService, pendingMode: $pendingCatalogMode)
            }
            Tab("My Collection", systemImage: "bookmark", value: .collection) {
                MyCollectionView(
                    dependencies: dependencies,
                    selectedTab: $selectedTab,
                    pendingCatalogMode: $pendingCatalogMode
                )
            }
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                ProfileView()
            }
            Tab(value: .search, role: .search) {
                SearchView(syncService: dependencies.syncService)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview("Tabs", traits: .sampleData) {
    MainTabView()
}

#Preview("iPad", traits: .sampleData, .landscapeLeft) {
    MainTabView()
}
