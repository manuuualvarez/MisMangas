//
//  ReadingEntry.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import WidgetKit

/// What the reading widget shows at one moment: the most recently changed mangas being read and
/// how many are being read in all.
struct ReadingEntry: TimelineEntry {
    let date: Date
    let items: [ReadingWidgetItem]
    /// Every manga being read, shown or not: the large widget says how many more there are.
    let totalReading: Int

    /// Made-up mangas for the gallery and for the widget while it loads; no store involved.
    static let placeholder = ReadingEntry(
        date: .now,
        items: [
            ReadingWidgetItem(id: 1, title: "Monster", coverFileURL: nil, readingVolume: 7, volumes: 18),
            ReadingWidgetItem(id: 2, title: "Dragon Ball", coverFileURL: nil, readingVolume: 12, volumes: 42),
            ReadingWidgetItem(id: 3, title: "Kingdom", coverFileURL: nil, readingVolume: 30, volumes: nil),
        ],
        totalReading: 3
    )

    /// Nothing being read, or a store the widget cannot read.
    static let empty = ReadingEntry(date: .now, items: [], totalReading: 0)
}
