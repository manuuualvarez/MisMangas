//
//  CollectionModeApplier.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftUI

/// My Collection's way of applying a mode: the collection has no catalog of its own, so a chip
/// in its detail closes the detail, leaves the mode for the catalog and switches to that tab,
/// which applies the mode when it sees it.
struct CollectionModeApplier: ApplyCatalogModeAction {
    @Binding var selectedTab: AppTab
    @Binding var pendingCatalogMode: CatalogMode?
    @Binding var selectedManga: Manga?

    func apply(_ mode: CatalogMode) {
        selectedManga = nil
        pendingCatalogMode = mode
        selectedTab = .catalog
    }
}
