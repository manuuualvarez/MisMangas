//
//  MangaSyncActor.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import SwiftData

/// The single write point of the store. Every method is one atomic change followed by an
/// explicit `save()`; autosave stays off everywhere else.
@ModelActor
actor MangaSyncActor {

    // MARK: - Catalog index

    /// Stores one server page of a catalog mode: upserts every manga (and its authors), then
    /// replaces the index rows of the mode from `(page - 1) * per` onwards. Page 1 therefore
    /// replaces the whole mode, and loading the same page twice never duplicates anything.
    /// `now` is stamped on `cachedAt`, `updatedAt` and `fetchedAt`.
    func replaceCatalogPage(modeKey: String, page: Int, per: Int, dtos: [MangaDTO], now: Date = .now) throws(PersistenceError) {
        let start = (page - 1) * per
        try run {
            let stale = FetchDescriptor<CatalogEntry>(
                predicate: #Predicate { $0.modeKey == modeKey && $0.ordinal >= start }
            )
            for entry in try modelContext.fetch(stale) {
                modelContext.delete(entry)
            }
            let authors = try upsertAuthors(dtos.flatMap(\.authors))
            let mangas = try upsertMangas(dtos, authors: authors, now: now)
            for (index, dto) in dtos.enumerated() {
                let entry = CatalogEntry(modeKey: modeKey, ordinal: start + index, fetchedAt: now)
                entry.manga = mangas[dto.id]
                modelContext.insert(entry)
            }
            try save()
        }
    }

    // MARK: - Purges

    /// Deletes index rows fetched before `now - olderThan`. Returns how many were removed.
    func purgeExpiredCatalog(olderThan: TimeInterval, now: Date = .now) throws(PersistenceError) -> Int {
        let cutoff = now.addingTimeInterval(-olderThan)
        return try run {
            let expired = try modelContext.fetch(FetchDescriptor<CatalogEntry>(predicate: #Predicate { $0.fetchedAt < cutoff }))
            for entry in expired {
                modelContext.delete(entry)
            }
            try save()
            return expired.count
        }
    }

    /// Deletes mangas that are neither in the collection nor indexed, and whose record is older
    /// than `now - olderThan`. Returns how many were removed.
    func purgeExpiredDetailCache(olderThan: TimeInterval, now: Date = .now) throws(PersistenceError) -> Int {
        let cutoff = now.addingTimeInterval(-olderThan)
        return try run {
            let unreferenced = FetchDescriptor<Manga>(
                predicate: #Predicate { !$0.inCollection && $0.catalogEntries.isEmpty }
            )
            let stale = try modelContext.fetch(unreferenced).filter { manga in
                guard let cachedAt = manga.cachedAt else {
                    return false
                }
                return cachedAt < cutoff
            }
            for manga in stale {
                modelContext.delete(manga)
            }
            try save()
            return stale.count
        }
    }
}

// MARK: - Helpers

private extension MangaSyncActor {
    /// Runs one write as a unit: on failure the pending changes are rolled back, so the next
    /// operation never commits a half-applied one, and the store error becomes `PersistenceError`.
    func run<T>(_ body: () throws -> T) throws(PersistenceError) -> T {
        do {
            return try body()
        } catch {
            modelContext.rollback()
            throw .saveFailed(error)
        }
    }

    func save() throws {
        guard modelContext.hasChanges else {
            return
        }
        try modelContext.save()
    }

    /// Reuses stored authors by id and inserts the unseen ones. Returns them keyed by id.
    func upsertAuthors(_ dtos: [AuthorDTO]) throws -> [UUID: Author] {
        let ids = Array(Set(dtos.map(\.id)))
        let stored = try modelContext.fetch(FetchDescriptor<Author>(predicate: #Predicate { ids.contains($0.id) }))
        var authors = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            if let existing = authors[dto.id] {
                dto.apply(to: existing)
            } else {
                let author = dto.makeAuthor()
                modelContext.insert(author)
                authors[dto.id] = author
            }
        }
        return authors
    }

    /// Refreshes stored mangas by id and inserts the unseen ones, linking their authors.
    func upsertMangas(_ dtos: [MangaDTO], authors: [UUID: Author], now: Date) throws -> [Int: Manga] {
        let ids = Array(Set(dtos.map(\.id)))
        let stored = try modelContext.fetch(FetchDescriptor<Manga>(predicate: #Predicate { ids.contains($0.id) }))
        var mangas = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for dto in dtos {
            let manga: Manga
            if let existing = mangas[dto.id] {
                dto.apply(to: existing)
                manga = existing
            } else {
                manga = dto.makeManga()
                modelContext.insert(manga)
                mangas[dto.id] = manga
            }
            manga.authors = dto.authors.compactMap { authors[$0.id] }
            manga.cachedAt = now
            manga.updatedAt = now
        }
        return mangas
    }
}
