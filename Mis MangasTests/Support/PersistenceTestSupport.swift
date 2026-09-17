//
//  PersistenceTestSupport.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData

/// Helpers shared by every persistence test: an isolated in-memory container per test, a fresh
/// `ModelContext` used as the oracle, and fixture-derived `MangaDTO` inputs.
///
/// The oracle of an actor or service test is always a **fresh** context over the same
/// container, never the actor's own context and never `mainContext`: what a fresh context
/// reads is exactly what the actor committed with `save()`.
enum PersistenceTestSupport {
    /// A `MangaSyncActor` over its own in-memory container. Each test calls this once, so
    /// suites stay parallelizable without `.serialized`.
    static func makeActor() throws -> (actor: MangaSyncActor, container: ModelContainer) {
        let container = try PersistenceController.makeInMemoryContainer()
        return (MangaSyncActor(modelContainer: container), container)
    }

    /// A brand-new context with autosave off: it only ever reads what is already in the store,
    /// and a test that mutates through it must call `save()` explicitly. Create it after the last
    /// `await` of the test and never use it across a suspension: it is not `Sendable`.
    static func freshContext(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    /// Every stored instance of `type`, optionally sorted. Without `sortBy` the order is
    /// unspecified and the caller sorts.
    static func fetchAll<T: PersistentModel>(
        _: T.Type,
        in context: ModelContext,
        sortBy: [SortDescriptor<T>] = []
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>(sortBy: sortBy))
    }

    /// Index entries of one catalog mode in ordinal order, exactly as the catalog screen reads them.
    static func catalogEntries(modeKey: String, in context: ModelContext) throws -> [CatalogEntry] {
        let descriptor = FetchDescriptor<CatalogEntry>(
            predicate: #Predicate { $0.modeKey == modeKey },
            sortBy: [SortDescriptor(\.ordinal)]
        )
        return try context.fetch(descriptor)
    }

    /// Stored mangas sorted by API id.
    static func mangasByID(in context: ModelContext) throws -> [Manga] {
        try fetchAll(Manga.self, in: context, sortBy: [SortDescriptor(\.id)])
    }

    /// The stored manga with the given API id, if any.
    static func manga(id: Int, in context: ModelContext) throws -> Manga? {
        var descriptor = FetchDescriptor<Manga>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The `items` of a paginated fixture (`mangas_page.json`, `mangas_page_best.json`, …)
    /// decoded with the app decoder.
    static func pageItems(_ fixture: String) throws -> [MangaDTO] {
        try JSONDecoder.app.decode(MangaPageDTO.self, from: TestFixtures.data(fixture)).items
    }

    /// Distinct author ids across a set of page items: the number of `Author` rows an upsert
    /// of those items must leave in the store.
    static func distinctAuthorCount(in dtos: [MangaDTO]) -> Int {
        Set(dtos.flatMap { $0.authors.map(\.id) }).count
    }
}

extension MangaDTO {
    /// A copy with some fields replaced. Used to derive "the same manga, refreshed" (new score)
    /// and "a second page of unseen mangas" (shifted ids) from the real fixtures.
    func replacing(id: Int? = nil, score: Double? = nil) -> MangaDTO {
        MangaDTO(
            id: id ?? self.id,
            title: title,
            titleEnglish: titleEnglish,
            titleJapanese: titleJapanese,
            synopsis: synopsis,
            background: background,
            startDate: startDate,
            endDate: endDate,
            score: score ?? self.score,
            status: status,
            chapters: chapters,
            volumes: volumes,
            mainPicture: mainPicture,
            url: url,
            authors: authors,
            genres: genres,
            themes: themes,
            demographics: demographics
        )
    }
}

extension Array where Element == MangaDTO {
    /// The same items with every id shifted by `offset`: a second page whose mangas are all
    /// new to the store but whose authors are the ones already persisted.
    func shiftingIDs(by offset: Int) -> [MangaDTO] {
        map { $0.replacing(id: $0.id + offset) }
    }
}
