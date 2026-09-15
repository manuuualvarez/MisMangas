//
//  MainTabView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Top-level tabs: a tab bar on iPhone, a sidebar-adaptable bar on iPad.
struct MainTabView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        TabView {
            Tab("Catalog", systemImage: "books.vertical") {
                CatalogView(syncService: dependencies.syncService)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview("Tabs", traits: .sampleData) {
    MainTabView()
}
