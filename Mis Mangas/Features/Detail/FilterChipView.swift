//
//  FilterChipView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

/// A category name as a capsule button. Tapping it asks the screen that shows the detail to
/// filter its catalog by that category. VoiceOver hears the name and its kind ("Romance, genre")
/// and the hint says what happens.
struct FilterChipView: View {
    let mode: CatalogMode
    let accessibilityLabel: String
    let hint: LocalizedStringKey
    @Environment(\.applyCatalogMode) private var applyCatalogMode

    var body: some View {
        Button(mode.title) {
            applyCatalogMode?.apply(mode)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .font(.subheadline)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(hint)
    }
}

#Preview("Chip", traits: .sampleData) {
    FilterChipView(
        mode: .byGenre("Romance"),
        accessibilityLabel: String(localized: "Romance, genre"),
        hint: "Shows mangas with this genre"
    )
}
