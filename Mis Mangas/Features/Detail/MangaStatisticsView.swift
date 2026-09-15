//
//  MangaStatisticsView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 15/09/2026.
//

import SwiftData
import SwiftUI

/// The VOLUMES / CHAPTERS row of the detail. A count the server did not send shows "—".
/// At accessibility text sizes the two cells stack, so the labels never hyphenate.
struct MangaStatisticsView: View {
    let volumes: Int?
    let chapters: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            LabeledContent("Volumes") { count(volumes) }
            Divider()
            LabeledContent("Chapters") { count(chapters) }
        }
        .labeledContentStyle(.statistic)
        // The divider would otherwise stretch the row to whatever height the parent offers.
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func count(_ value: Int?) -> some View {
        if let value {
            Text(value, format: .number)
        } else {
            Text(verbatim: "—")
                .accessibilityLabel("Not available")
        }
    }
}

#Preview("Both counts", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaStatisticsView(volumes: manga.volumes, chapters: manga.chapters).padding() }
}

#Preview("Missing chapters", traits: .sampleData) {
    MangaStatisticsView(volumes: 41, chapters: nil).padding()
}
