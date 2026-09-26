//
//  ReadingWidgetLargeView.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The large widget: up to six mangas in rows, each with its cover, title, volume and a progress
/// bar when the volume count is known, and how many more are being read. Each row opens its own
/// manga.
struct ReadingWidgetLargeView: View {
    let items: [ReadingWidgetItem]
    /// Every manga being read, shown or not.
    let totalReading: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Six rows fit at the default text sizes; with larger text only four do, and the rest count
    /// as more.
    private var visibleItems: ArraySlice<ReadingWidgetItem> {
        items.prefix(dynamicTypeSize >= .xxLarge ? 4 : 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(visibleItems) { item in
                Link(destination: item.deepLink) {
                    HStack(spacing: 10) {
                        // At most 40×56: six rows share the widget's height, which on smaller
                        // phones is less than six full-size covers.
                        WidgetCoverImage(fileURL: item.coverFileURL)
                            .aspectRatio(40 / 56, contentMode: .fit)
                            .frame(maxWidth: 40, maxHeight: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(item.volumeText)
                                .font(.caption)
                                .foregroundStyle(.mmSecondaryLabel)
                                .widgetAccentable()
                            if let progress = item.progress {
                                ProgressView(value: progress)
                                    .widgetAccentable()
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.accessibilityLabel)
                }
            }
            if totalReading > visibleItems.count {
                Text("+\(totalReading - visibleItems.count) more")
                    .font(.caption)
                    .foregroundStyle(.mmSecondaryLabel)
                    .widgetAccentable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview(as: .systemLarge) {
    ReadingWidget()
} timeline: {
    ReadingEntry(date: .now, items: ReadingEntry.placeholder.items, totalReading: 9)
    ReadingEntry.placeholder
    ReadingEntry.empty
}
