//
//  ReadingWidgetEmptyView.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The widget with nothing being read: a title and where to start. On the Lock Screen only the
/// title fits.
struct ReadingWidgetEmptyView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing in progress")
                .font(.headline)
            if !family.isAccessory {
                Text("Add a manga in Mis Mangas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            true
        default:
            false
        }
    }
}

#Preview(as: .systemSmall) {
    ReadingWidget()
} timeline: {
    ReadingEntry.empty
}
