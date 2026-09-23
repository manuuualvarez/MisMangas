//
//  EnvironmentValues+ApplyCatalogMode.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

extension EnvironmentValues {
    /// Set by every screen that presents manga details; `nil` where no screen does, so a chip
    /// outside one has nothing to apply the mode to.
    @Entry var applyCatalogMode: (any ApplyCatalogModeAction)?
}
