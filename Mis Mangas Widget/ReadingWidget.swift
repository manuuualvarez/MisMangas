//
//  ReadingWidget.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The mangas the reader is reading and where they are in each one, on the Home Screen and the
/// Lock Screen. Static: no configuration and no interaction besides opening the app.
struct ReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: .readingWidgetKind, provider: ReadingTimelineProvider()) { entry in
            ReadingWidgetView(entry: entry)
        }
        .configurationDisplayName("Reading")
        .description("The mangas you are reading and where you are in each one.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}
