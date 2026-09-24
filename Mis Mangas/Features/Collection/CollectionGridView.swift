//
//  CollectionGridView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// My Collection as covers under the summary, in the catalog's adaptive grid. Tapping a cell
/// selects its manga; the owner presents the selection. The column width scales with the text
/// size, so larger text gets fewer, wider columns.
struct CollectionGridView: View {
    let mangas: [Manga]
    let stats: CollectionStats
    @Binding var selection: Manga?
    let namespace: Namespace.ID

    @ScaledMetric(relativeTo: .subheadline) private var minimumColumnWidth: CGFloat = 110

    var body: some View {
        ScrollView {
            CollectionStatsCard(stats: stats)
                .padding(.horizontal)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: 12)], alignment: .leading, spacing: 16) {
                ForEach(mangas) { manga in
                    Button {
                        selection = manga
                    } label: {
                        CatalogGridCellView(manga: manga, namespace: namespace, isSelected: selection == manga)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview("Grid", traits: .sampleData) {
    @Previewable @Query(filter: #Predicate<Manga> { $0.inCollection == true }, sort: \Manga.title) var mangas: [Manga]
    @Previewable @State var selection: Manga?
    @Previewable @Namespace var namespace
    CollectionGridView(mangas: mangas, stats: CollectionStats(mangas: mangas), selection: $selection, namespace: namespace)
}
