//
//  SelectedModeApplier.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

/// The catalog's way of applying a mode: write it into the screen's selection, which rebuilds the
/// list and loads the first page. Clearing the manga covers the mode that is applied again, where
/// the selection does not change and nothing else would close the detail.
struct SelectedModeApplier: ApplyCatalogModeAction {
    @Binding var mode: CatalogMode
    @Binding var selectedManga: Manga?

    func apply(_ mode: CatalogMode) {
        selectedManga = nil
        self.mode = mode
    }
}
