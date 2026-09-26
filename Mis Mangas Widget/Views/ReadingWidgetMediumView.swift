//
//  ReadingWidgetMediumView.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The medium widget: the three most recently changed mangas side by side, each with its cover,
/// title and volume ("7/42"), and each opening its own manga.
struct ReadingWidgetMediumView: View {
    /// The mangas to show; only the first three fit.
    let items: [ReadingWidgetItem]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(items.prefix(3)) { item in
                Link(destination: item.deepLink) {
                    VStack(alignment: .leading, spacing: 2) {
                        WidgetCoverImage(fileURL: item.coverFileURL)
                            .aspectRatio(0.7, contentMode: .fit)
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2, reservesSpace: true)
                        Text(item.shortVolumeText)
                            .font(.caption2)
                            .foregroundStyle(.mmSecondaryLabel)
                            .widgetAccentable()
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.accessibilityLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview(as: .systemMedium) {
    ReadingWidget()
} timeline: {
    ReadingEntry.placeholder
    ReadingEntry.empty
}
