//
//  TaxonomySectionView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftUI

/// One category of the advanced search form: a group collapsed until asked for, since the server
/// lists dozens of names and expanded they bury everything below them. Inside, the names as
/// chips, a spinner while the lists are on their way, or the list's failure with a retry.
struct TaxonomySectionView: View {
    let title: LocalizedStringKey
    let unavailableTitle: LocalizedStringKey
    let expandHint: LocalizedStringKey
    let collapseHint: LocalizedStringKey
    /// `nil` until the first load; empty after a failed one.
    let options: [String]?
    let error: APIError?
    @Binding var selection: Set<String>
    let retry: () -> Void
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let options {
                    if options.isEmpty, let error {
                        Text(unavailableTitle)
                        InlineErrorView(error: error, retry: retry)
                    } else {
                        MultiSelectChipsView(title: title, options: options, selection: $selection)
                    }
                } else {
                    ProgressView()
                        .accessibilityLabel("Loading")
                }
            } label: {
                // The count rides in the value, not in the name: read as part of the label a
                // screen reader would say the middle dot out loud, and the hint is what tells
                // whether tapping opens or closes the group.
                if selection.isEmpty {
                    Text(title)
                        .accessibilityHint(isExpanded ? collapseHint : expandHint)
                } else {
                    Text("\(Text(title)) · \(selection.count)")
                        .accessibilityLabel(title)
                        .accessibilityValue("\(selection.count) selected")
                        .accessibilityHint(isExpanded ? collapseHint : expandHint)
                }
            }
        }
    }
}

#Preview("States", traits: .sampleData) {
    @Previewable @State var selection: Set = ["Action"]
    Form {
        TaxonomySectionView(title: "Genres", unavailableTitle: "Couldn't load genres", expandHint: "Expands the genres", collapseHint: "Collapses the genres", options: ["Action", "Adventure"], error: nil, selection: $selection) {}
        TaxonomySectionView(title: "Themes", unavailableTitle: "Couldn't load themes", expandHint: "Expands the themes", collapseHint: "Collapses the themes", options: [], error: .serverError, selection: .constant([])) {}
        TaxonomySectionView(title: "Demographics", unavailableTitle: "Couldn't load demographics", expandHint: "Expands the demographics", collapseHint: "Collapses the demographics", options: nil, error: nil, selection: .constant([])) {}
    }
}
