//
//  ReadingItemsFetcher.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
import SwiftData

/// Reads the mangas being read from the shared store for the widget, with a context of its own per
/// call, and hands back values: no model leaves the context.
///
/// Being read means a volume being read and a collection not marked complete; the last volume
/// still counts. Most recently changed entry first: the catalog also stamps the manga's own date.
struct ReadingItemsFetcher {
    /// The most mangas the widget shows; the app keeps the covers of as many.
    static let itemLimit = 6

    let container: ModelContainer
    let covers: CoverCacheFiles?

    /// The `limit` most recently changed mangas being read, and how many are being read in all.
    func fetch(limit: Int) throws -> (items: [ReadingWidgetItem], total: Int) {
        let context = ModelContext(container)
        // The manga is part of the condition, so the limit and the total count the same entries.
        let isReading = #Predicate<UserCollectionEntry> {
            $0.manga != nil && $0.readingVolume != nil && $0.completeCollection == false
        }
        var descriptor = FetchDescriptor(predicate: isReading, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        // A count loads no model: it runs without the limit so the widget can say how many more.
        let total = try context.fetchCount(descriptor)
        descriptor.fetchLimit = limit
        let items = try context.fetch(descriptor).compactMap { entry -> ReadingWidgetItem? in
            guard let manga = entry.manga, let readingVolume = entry.readingVolume else {
                return nil
            }
            return ReadingWidgetItem(
                id: manga.id,
                title: manga.title,
                coverFileURL: covers?.existingFileURL(for: manga.id),
                readingVolume: readingVolume,
                volumes: manga.volumes
            )
        }
        return (items, total)
    }
}
