//
//  ReadingWidgetAccessoryRectangularView.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The rectangular Lock Screen widget: the most recently changed manga's title, the volume being
/// read and a progress bar when the volume count is known. Tapping it opens the manga.
struct ReadingWidgetAccessoryRectangularView: View {
    let item: ReadingWidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.headline)
                .lineLimit(1)
            Text(item.volumeText)
                .font(.caption)
                .widgetAccentable()
            if let progress = item.progress {
                Gauge(value: progress) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .widgetURL(item.deepLink)
    }
}

#Preview(as: .accessoryRectangular) {
    ReadingWidget()
} timeline: {
    ReadingEntry.placeholder
    ReadingEntry.empty
}
