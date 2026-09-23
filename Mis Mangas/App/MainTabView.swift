//
//  MainTabView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Top-level tabs: a tab bar on iPhone, a sidebar-adaptable bar on iPad. Search is the tab with
/// that role: the system draws it apart from the others and hosts its field.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TabView {
            Tab("Catalog", systemImage: "books.vertical") {
                CatalogView(syncService: dependencies.syncService)
            }
            Tab(role: .search) {
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
