//
//  MultiSelectChipsView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 18/09/2026.
//

import SwiftUI

/// The names of one category as capsule buttons that can be picked in any number: a picked name
/// is filled, tapping it again drops it. The group carries the name of its category so VoiceOver
/// says which chips these are, and every chip says whether it is selected.
struct MultiSelectChipsView: View {
    /// A key, not a plain string: as `String` the accessible label of the group would skip
    /// the string catalog and stay in English.
    let title: LocalizedStringKey
    let options: [String]
    @Binding var selection: Set<String>
    // Chips grow with Dynamic Type; at accessibility sizes a fixed gap reads as one block.
    @ScaledMetric private var chipSpacing: CGFloat = 6

    var body: some View {
        FlowLayout(spacing: chipSpacing) {
            // Picked and not picked are two button styles, and a style is a type: one branch each.
            ForEach(options, id: \.self) { option in
                if selection.contains(option) {
                    Button(option) { selection.remove(option) }
                        .buttonStyle(.borderedProminent)
                        .tint(.mmAccentFill)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .font(.subheadline)
                        .accessibilityAddTraits(.isSelected)
                } else {
                    Button(option) { selection.insert(option) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .font(.subheadline)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

#Preview("Chips", traits: .sampleData) {
    @Previewable @State var selection: Set = ["Adventure"]
    Form {
        Section("Genres") {
            MultiSelectChipsView(
                title: "Genres",
                options: ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Slice of Life"],
                selection: $selection
            )
        }
    }
}
