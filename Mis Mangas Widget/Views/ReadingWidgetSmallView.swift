//
//  ReadingWidgetSmallView.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The small widget: the most recently changed manga, with a large cover, its title, the volume
/// being read and a ring with the progress when the volume count is known. Tapping it opens the
/// manga.
struct ReadingWidgetSmallView: View {
    let item: ReadingWidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                WidgetCoverImage(fileURL: item.coverFileURL)
                    .aspectRatio(0.7, contentMode: .fit)
                Spacer(minLength: 0)
                if let progress = item.progress {
                    Gauge(value: progress) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(item.readingVolume, format: .number)
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .widgetAccentable()
                }
            }
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            Text(item.volumeText)
                .font(.caption)
                .foregroundStyle(.mmSecondaryLabel)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .widgetURL(item.deepLink)
    }
}

#Preview(as: .systemSmall) {
    ReadingWidget()
} timeline: {
    ReadingEntry.placeholder
    ReadingEntry(
        date: .now,
        items: ReadingEntry.placeholder.items.filter { $0.volumes == nil },
        totalReading: 1
    )
    ReadingEntry.empty
}
