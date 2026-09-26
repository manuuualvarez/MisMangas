//
//  ReadingWidgetView.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The reading widget for one entry: the layout of the family it is shown in, or nothing in
/// progress when no manga is being read.
struct ReadingWidgetView: View {
    let entry: ReadingEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let first = entry.items.first {
                switch family {
                case .systemMedium:
                    ReadingWidgetMediumView(items: entry.items)
                case .systemLarge:
                    ReadingWidgetLargeView(items: entry.items, totalReading: entry.totalReading)
                case .accessoryRectangular:
                    ReadingWidgetAccessoryRectangularView(item: first)
                case .accessoryCircular:
                    ReadingWidgetAccessoryCircularView(item: first)
                default:
                    ReadingWidgetSmallView(item: first)
                }
            } else {
                ReadingWidgetEmptyView()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

#Preview(as: .systemMedium) {
    ReadingWidget()
} timeline: {
    ReadingEntry.placeholder
    ReadingEntry.empty
}
