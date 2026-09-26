//
//  ReadingWidgetEmptyView.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftUI
import WidgetKit

/// The widget with nothing being read: a title and where to start. On the rectangular Lock Screen
/// widget only the title fits, and the circular one shows a closed book.
struct ReadingWidgetEmptyView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "book.closed")
                    .font(.title2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nothing in progress")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing in progress")
                    .font(.headline)
                if !family.isAccessory {
                    Text("Add a manga in Mis Mangas")
                        .font(.caption)
                        .foregroundStyle(.mmSecondaryLabel)
                }
            }
            .accessibilityElement(children: .combine)
        }
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
