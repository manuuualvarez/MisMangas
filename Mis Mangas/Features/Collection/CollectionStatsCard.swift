//
//  CollectionStatsCard.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import SwiftData
import SwiftUI

/// The summary above My Collection: how many series, how many volumes owned and the share of
/// complete series. Side by side while they fit, stacked at larger text sizes. Read as one
/// sentence by VoiceOver.
struct CollectionStatsCard: View {
    let stats: CollectionStats

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let percent = stats.completeRatio.formatted(.percent.precision(.fractionLength(0)))
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.total.formatted())
                    .font(.title2.bold())
                Text("Series")
                    .font(.caption)
                    .foregroundStyle(.mmSecondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.volumesOwned.formatted())
                    .font(.title2.bold())
                Text("Volumes")
                    .font(.caption)
                    .foregroundStyle(.mmSecondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(percent)
                    .font(.title2.bold())
                Text("Complete")
                    .font(.caption)
                    .foregroundStyle(.mmSecondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("^[\(stats.total) series](inflect: true), ^[\(stats.volumesOwned) volume](inflect: true), \(percent) complete"))
    }
}

#Preview("Stats", traits: .sampleData) {
    @Previewable @Query(filter: #Predicate<Manga> { $0.inCollection == true }) var mangas: [Manga]
    CollectionStatsCard(stats: CollectionStats(mangas: mangas)).padding()
}
