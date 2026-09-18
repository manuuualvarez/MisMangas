//
//  SearchModeApplier.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

/// The search screen's way of applying a mode: clear the selected manga (the detail closes),
/// empty the field so no stale suggestions hang over the new results, and load the mode through
/// the screen's own view model, whose current mode drives the results. The task is there because
/// the load is asynchronous, not for isolation: the protocol and the view model both run on the
/// main actor.
struct SearchModeApplier: ApplyCatalogModeAction {
    let viewModel: CatalogViewModel
    @Binding var selectedManga: Manga?

    func apply(_ mode: CatalogMode) {
        selectedManga = nil
        viewModel.searchText = ""
        Task { await viewModel.loadInitial(mode: mode) }
    }
}
