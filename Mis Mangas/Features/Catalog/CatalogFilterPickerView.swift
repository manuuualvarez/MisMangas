//
//  CatalogFilterPickerView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftUI

/// One category of the filter form: a picker with "Any" plus the server's names, a spinner
/// while the lists are on their way, or the list's failure with a retry when it did not arrive.
/// A selection the server no longer lists (a filter applied in an earlier session) stays
/// visible as the last option, so the picker never shows a blank value.
struct CatalogFilterPickerView: View {
    let title: LocalizedStringKey
    let unavailableTitle: LocalizedStringKey
    /// `nil` until the first load; empty after a failed one.
    let options: [String]?
    let error: APIError?
    @Binding var selection: String?
    let retry: () -> Void

    var body: some View {
        Section {
            if let options {
                if options.isEmpty, let error {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(unavailableTitle)
                        InlineErrorView(error: error, retry: retry)
                    }
                } else {
                    Picker(title, selection: $selection) {
                        Text("Any").tag(String?.none)
                        ForEach(pickerOptions(from: options), id: \.self) { option in
                            Text(option).tag(Optional(option))
                        }
                    }
                }
            } else {
                LabeledContent(title) {
                    ProgressView()
                        .accessibilityLabel("Loading")
                }
            }
        }
    }

    private func pickerOptions(from options: [String]) -> [String] {
        guard let selection, !options.contains(selection) else {
            return options
        }
        return options + [selection]
    }
}

#Preview("States", traits: .sampleData) {
    @Previewable @State var selection: String? = "Romance"
    Form {
        CatalogFilterPickerView(title: "Genre", unavailableTitle: "Couldn't load genres", options: ["Action", "Romance"], error: nil, selection: $selection) {}
        CatalogFilterPickerView(title: "Theme", unavailableTitle: "Couldn't load themes", options: [], error: .serverError, selection: $selection) {}
        CatalogFilterPickerView(title: "Demographic", unavailableTitle: "Couldn't load demographics", options: nil, error: nil, selection: $selection) {}
    }
}
