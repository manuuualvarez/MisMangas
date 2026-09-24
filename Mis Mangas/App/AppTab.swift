//
//  AppTab.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

/// The top-level tabs, as the selection of the tab view. Every tab carries a value, the search
/// tab included: a tab view with a selection only accepts tabs of its selection type.
enum AppTab: Hashable {
    case catalog
    case collection
    case search
}
