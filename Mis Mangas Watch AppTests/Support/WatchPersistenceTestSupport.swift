//
//  WatchPersistenceTestSupport.swift
//  Mis Mangas Watch AppTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas_Watch_App
import SwiftData

/// Helpers shared by the watch tests that touch the store: an isolated in-memory container per
/// test, a fresh `ModelContext` used as the oracle, seeding with dates chosen by the test, and a
/// bounded wait for effects produced on tasks the test does not await.
///
/// The oracle is always a **fresh** context over the same container, never the actor's own
/// context: what a fresh context reads is exactly what the actor committed with `save()`.
enum WatchPersistenceTestSupport {
    /// The user's side of a seeded manga.
    struct Entry {
        var readingVolume: Int?
        var completeCollection = false
        /// Stamped as both `createdAt` and `updatedAt` of the entry.
        var updatedAt: Date
    }

    /// A `MangaSyncActor` over its own in-memory container. Each test calls this once, so suites
    /// stay parallelizable.
    static func makeActor() throws -> (actor: MangaSyncActor, container: ModelContainer) {
        let container = try PersistenceController.makeInMemoryContainer()
        return (MangaSyncActor(modelContainer: container), container)
    }

    /// A brand-new context with autosave off. Create it after the last `await` that changes the
    /// store and never keep it across a suspension: it is not `Sendable`.
    static func freshContext(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    /// Every stored instance of `type`, optionally sorted.
    static func fetchAll<T: PersistentModel>(
        _: T.Type,
        in context: ModelContext,
        sortBy: [SortDescriptor<T>] = []
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>(sortBy: sortBy))
    }

    /// The stored manga with the given id, if any.
    static func manga(id: Int, in context: ModelContext) throws -> Manga? {
        var descriptor = FetchDescriptor<Manga>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The stored collection entry of `mangaID`, if any.
    static func entry(mangaID: Int, in context: ModelContext) throws -> UserCollectionEntry? {
        var descriptor = FetchDescriptor<UserCollectionEntry>(predicate: #Predicate { $0.mangaID == mangaID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Stored manga ids, ascending.
    static func mangaIDs(in container: ModelContainer) throws -> [Int] {
        try fetchAll(Manga.self, in: freshContext(container)).map(\.id).sorted()
    }

    /// Manga ids of the stored collection entries, ascending.
    static func entryMangaIDs(in container: ModelContainer) throws -> [Int] {
        try fetchAll(UserCollectionEntry.self, in: freshContext(container)).map(\.mangaID).sorted()
    }

    /// Stores one manga and, with `entry`, its collection entry, through a fresh context and an
    /// explicit `save()`, so nothing goes through the code under test.
    static func insertManga(
        id: Int,
        title: String = "Manga",
        volumes: Int?,
        coverURL: String? = nil,
        updatedAt: Date,
        entry: Entry?,
        in container: ModelContainer
    ) throws {
        let context = freshContext(container)
        let manga = Manga(
            id: id,
            title: title,
            status: MangaStatus.finished.rawValue,
            score: 8,
            volumes: volumes,
            mainPictureURL: coverURL,
            inCollection: entry != nil,
            updatedAt: updatedAt
        )
        context.insert(manga)
        if let entry {
            let stored = UserCollectionEntry(
                mangaID: id,
                readingVolume: entry.readingVolume,
                completeCollection: entry.completeCollection,
                createdAt: entry.updatedAt,
                updatedAt: entry.updatedAt
            )
            context.insert(stored)
            stored.manga = manga
        }
        try context.save()
    }

    /// Polls `condition` every few milliseconds and returns `true` as soon as it holds, or `false`
    /// once `timeout` elapses or the calling task is cancelled, so a missing effect fails the test
    /// instead of hanging it.
    static func waitUntil(timeout: Duration = .seconds(3), _ condition: () async throws -> Bool) async rethrows -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if try await condition() {
                return true
            }
            guard ContinuousClock.now < deadline else {
                return false
            }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
    }
}
