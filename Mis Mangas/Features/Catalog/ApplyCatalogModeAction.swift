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
///
/// Isolated to the main actor because every conformer mutates UI state: bindings into a
/// screen's `@State` or a `@MainActor` view model. The compiler would not demand it (a
/// binding's setter is `nonisolated`), so without the annotation nothing would stop a future
/// conformer from being called off the main actor; with it, the contract is checked at every
/// call site and a conformer can talk to a view model without wrapping the call in a task.
@MainActor
protocol ApplyCatalogModeAction {
    /// Applies `mode` to the catalog behind the detail and closes the detail.
    func apply(_ mode: CatalogMode)
}
