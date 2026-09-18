//
//  SearchSuggestionsView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import SwiftData
import SwiftUI

/// The title suggestions for the text being typed, read from the store under the key the view
/// model set for them, in server order. Tapping one selects its manga: the owner presents the
/// detail and the search stays as it was, so going back returns to the field and its text.
/// At accessibility text sizes the title moves under the cover instead of squeezing beside it.
struct SearchSuggestionsView: View {
    @Query private var entries: [CatalogEntry]
    @Binding var selection: Manga?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(modeKey: String, selection: Binding<Manga?>) {
        _entries = Query(filter: #Predicate<CatalogEntry> { $0.modeKey == modeKey }, sort: \.ordinal)
        _selection = selection
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        ForEach(entries) { entry in
            if let manga = entry.manga {
                Button {
                    selection = manga
                } label: {
                    layout {
                        MangaCoverView(manga: manga, size: .thumbnail)
                        Text(manga.title)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel(manga.title)
                .accessibilityHint("Opens the manga")
            }
        }
    }
}

#Preview("Suggestions", traits: .sampleData) {
    @Previewable @State var selection: Manga?
    List {
        SearchSuggestionsView(modeKey: "all", selection: $selection)
    }
}
