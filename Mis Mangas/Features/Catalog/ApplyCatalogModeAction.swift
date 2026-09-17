//
//  ApplyCatalogModeAction.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

/// Shows a catalog mode on the screen that owns the current manga detail, closing the detail.
/// A chip or an author name in the detail publishes the intent; the screen that presented the
/// detail decides how a mode is shown (a state change, a view model call) by injecting its own
/// conformer into the environment.
///
/// A value with a method instead of a closure, on purpose: SwiftUI compares the old and new
/// value of every environment key to decide which readers re-evaluate, and function values
/// cannot be compared, so a closure would invalidate every reader on every write. A struct
/// compares field by field, so readers stay put while nothing changed.
protocol ApplyCatalogModeAction {
    /// Applies `mode` to the catalog behind the detail and closes the detail.
    func apply(_ mode: CatalogMode)
}
