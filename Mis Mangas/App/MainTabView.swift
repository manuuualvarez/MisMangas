//
//  MainTabView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Top-level tabs: a tab bar on iPhone, a sidebar-adaptable bar on iPad. Search is the tab with
/// that role: the system draws it apart from the others and hosts its field. The selected tab is
/// state here so My Collection can send the user to the catalog, with a mode to apply there, and a
/// link to a manga can open it in My Collection.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Binding var pendingMangaID: Int?
    @State private var selectedTab = AppTab.catalog
    @State private var pendingCatalogMode: CatalogMode?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Catalog", systemImage: "books.vertical", value: .catalog) {
                CatalogView(syncService: dependencies.syncService, pendingMode: $pendingCatalogMode)
                    .tint(.accent)
            }
            Tab("My Collection", systemImage: "bookmark", value: .collection) {
                MyCollectionView(
                    dependencies: dependencies,
                    selectedTab: $selectedTab,
                    pendingCatalogMode: $pendingCatalogMode,
                    pendingMangaID: $pendingMangaID
                )
                .tint(.accent)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                ProfileView()
                    .tint(.accent)
            }
            Tab(value: .search, role: .search) {
                SearchView(syncService: dependencies.syncService)
                    .tint(.accent)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The selected tab is purple text on the tab bar but a purple fill under white text in
        // the iPad sidebar, and in dark mode no single purple passes both: the tabs stay neutral
        // and each tab's content gets the accent back.
        .tint(.primary)
        // Also on appearing: a link that arrived before the tabs showed waits for them.
        .onChange(of: pendingMangaID, initial: true) { _, mangaID in
            if mangaID != nil {
                selectedTab = .collection
            }
        }
    }
}

#Preview("Tabs", traits: .sampleData) {
    @Previewable @State var pendingMangaID: Int?
    MainTabView(pendingMangaID: $pendingMangaID)
}

#Preview("iPad", traits: .sampleData, .landscapeLeft) {
    @Previewable @State var pendingMangaID: Int?
    MainTabView(pendingMangaID: $pendingMangaID)
}

#Preview("Link", traits: .sampleData) {
    @Previewable @State var pendingMangaID = SampleData.collection.first?.manga.id
    MainTabView(pendingMangaID: $pendingMangaID)
}
