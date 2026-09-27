//
//  ReadingTimelineProvider.swift
//  Mis Mangas Widget
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import OSLog
import SwiftData
import WidgetKit

/// Reads the shared store and hands WidgetKit a single entry. WidgetKit offers only this
/// completion-handler provider for a static configuration; the read is synchronous and short (a
/// few rows), so each completion is called right after it, without a task. The timeline never asks
/// for a reload by itself: the app reloads the widget whenever the collection changes.
struct ReadingTimelineProvider: TimelineProvider {
    /// The app's store in the App Group container, opened once per process; `nil` when it cannot
    /// be opened, and the widget then shows nothing in progress.
    private static let container: ModelContainer? = {
        do {
            return try PersistenceController.makeContainer()
        } catch {
            Logger.widget.error("Store not opened: \(String(describing: error), privacy: .private)")
            return nil
        }
    }()

    func placeholder(in _: Context) -> ReadingEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ReadingEntry) -> Void) {
        completion(context.isPreview ? .placeholder : makeEntry())
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<ReadingEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }

    private func makeEntry() -> ReadingEntry {
        let signposter = OSSignposter.app
        let interval = signposter.beginInterval(SignpostName.widgetTimeline, id: signposter.makeSignpostID())
        defer { signposter.endInterval(SignpostName.widgetTimeline, interval) }
        guard let container = Self.container else {
            return .empty
        }
        do {
            let reading = try ReadingItemsFetcher(container: container, covers: .appGroup)
                .fetch(limit: ReadingItemsFetcher.itemLimit)
            return ReadingEntry(date: .now, items: reading.items, totalReading: reading.total)
        } catch {
            Logger.widget.error("Reading list not read: \(String(describing: error), privacy: .private)")
            return .empty
        }
    }
}
