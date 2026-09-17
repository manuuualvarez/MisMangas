//
//  SelectedModeApplier.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

/// The catalog's way of applying a mode: clear the selected manga (the detail closes) and write
/// the mode into the screen's selection, which rebuilds the list and loads the first page.
struct SelectedModeApplier: ApplyCatalogModeAction {
    @Binding var mode: CatalogMode
    @Binding var selectedManga: Manga?

    func apply(_ mode: CatalogMode) {
        selectedManga = nil
        self.mode = mode
    }
}
