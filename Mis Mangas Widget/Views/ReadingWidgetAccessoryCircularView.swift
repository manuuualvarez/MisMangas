//
//  ReadingWidgetAccessoryCircularView.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The circular Lock Screen widget: the volume being read over the volume count, in a ring with
/// the progress; the volume alone, without a ring, while the count is unknown. Tapping it opens
/// the manga.
struct ReadingWidgetAccessoryCircularView: View {
    let item: ReadingWidgetItem

    var body: some View {
        ZStack {
            if let volumes = item.volumes, let progress = item.progress {
                Gauge(value: progress) {
                    Text(volumes, format: .number)
                } currentValueLabel: {
                    Text(item.readingVolume, format: .number)
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                AccessoryWidgetBackground()
                Text(item.readingVolume, format: .number)
                    .font(.title2.weight(.semibold))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .widgetURL(item.deepLink)
    }
}

#Preview(as: .accessoryCircular) {
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
