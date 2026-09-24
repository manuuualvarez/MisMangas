//
//  MangaSyncActor.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import SwiftData

/// The single write point of the store. Every method is one atomic change followed by an
/// explicit `save()`; autosave stays off everywhere else. A decision that spans more than one
/// read or write lives here, as one synchronous method: callers never chain two actor calls
/// whose combination must stay consistent.
@ModelActor
actor MangaSyncActor {

    // MARK: - Catalog index

    /// Stores one server page of a catalog mode: upserts every manga (and its authors), then
    /// replaces the index rows of the mode from `(page - 1) * per` onwards. Page 1 therefore
    /// replaces the whole mode, and loading the same page twice never duplicates anything.
    /// `now` is stamped on `cachedAt`, `updatedAt` and `fetchedAt`.
    /// Throws `.cancelled` without touching the store when the calling task was cancelled before
    /// the write started: its caller has moved on, and the page would only leave rows no screen
    /// shows. A cancellation that arrives during the write does not undo it.
    func replaceCatalogPage(modeKey: String, page: Int, per: Int, dtos: [MangaDTO], now: Date = .now) throws(PersistenceError) {
        guard !Task.isCancelled else {
            throw .cancelled
        }
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

    /// How many index rows `modeKey` holds right now. The index of a mode belongs to the whole
    /// app, so a screen cannot tell from its own memory how much of it is still there.
    func indexedCount(modeKey: String) throws(PersistenceError) -> Int {
        try run {
            try modelContext.fetchCount(FetchDescriptor<CatalogEntry>(predicate: #Predicate { $0.modeKey == modeKey }))
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

    // MARK: - Detail cache

    /// Stores one manga as `/search/manga/{id}` serves it, with its authors, stamped with `now`.
    /// Leaves the collection and the catalog index untouched. Returns the manga id.
    func cacheDetail(_ dto: MangaDTO, now: Date = .now) throws(PersistenceError) -> Int {
        try run {
            _ = try upsertManga(dto, now: now)
            try save()
            return dto.id
        }
    }

    // MARK: - Collection

    /// Saves the entry of a stored manga and queues its upload, in one transaction: the entry
    /// and the pending operation are always written together. Throws `.notFound` when the
    /// manga is not stored: an entry always hangs from its manga.
    func saveCollectionEntry(
        mangaID: Int,
        volumesOwned: [Int],
        readingVolume: Int?,
        completeCollection: Bool,
        now: Date = .now
    ) throws(PersistenceError) {
        let isStored = try run {
            guard let manga = try fetchOne(#Predicate<Manga> { $0.id == mangaID }) else {
                return false
            }
            let entry = try applyEntry(
                to: manga,
                volumesOwned: volumesOwned,
                readingVolume: readingVolume,
                completeCollection: completeCollection,
                now: now
            )
            let payload = try JSONEncoder.app.encode(entry.toRequest())
            try replacePendingOperation(.upsert, mangaID: mangaID, payload: payload, now: now)
            try save()
            return true
        }
        guard isStored else {
            throw .notFound
        }
    }

    /// Removes the entry of `mangaID`, takes the manga out of the collection and queues the
    /// deletion, in one transaction. The manga stays cached. The deletion is queued even
    /// without a local entry: the server may still hold one.
    func removeCollectionEntry(mangaID: Int, now: Date = .now) throws(PersistenceError) {
        try run {
            if let entry = try fetchOne(#Predicate<UserCollectionEntry> { $0.mangaID == mangaID }) {
                modelContext.delete(entry)
            }
            if let manga = try fetchOne(#Predicate<Manga> { $0.id == mangaID }), manga.inCollection {
                manga.inCollection = false
                manga.updatedAt = now
            }
            try replacePendingOperation(.delete, mangaID: mangaID, payload: nil, now: now)
            try save()
        }
    }

    /// Stores an entry as the server returns it: the nested manga as `cacheDetail` would, then
    /// the entry under the same rules as a local save (local id, normalized volumes). This is the
    /// server's truth, so it bypasses the outbox: never call it for a manga with a queued
    /// operation, or the queue would stop matching the entry. Previews use it to seed the store.
    func upsertCollectionEntry(from dto: UserMangaCollectionDTO, now: Date = .now) throws(PersistenceError) {
        try run {
            let manga = try upsertManga(dto.manga, now: now)
            try applyEntry(
                to: manga,
                volumesOwned: dto.volumesOwned,
                readingVolume: dto.readingVolume,
                completeCollection: dto.completeCollection,
                now: now
            )
            try save()
        }
    }

    /// Every entry of the collection, in no particular order.
    func collectionSnapshot() throws(PersistenceError) -> [CollectionEntrySnapshot] {
        try run {
            try modelContext.fetch(FetchDescriptor<UserCollectionEntry>()).map { entry in
                CollectionEntrySnapshot(
                    mangaID: entry.mangaID,
                    volumesOwned: entry.volumesOwned,
                    readingVolume: entry.readingVolume,
                    completeCollection: entry.completeCollection,
                    updatedAt: entry.updatedAt
                )
            }
        }
    }

    // MARK: - Outbox

    /// The operations ready to send, oldest first; blocked ones wait for `unblockAll()`. The
    /// operations stay stored until they are marked completed.
    func drainPendingOperations() throws(PersistenceError) -> [PendingOperationSnapshot] {
        try run {
            let ready = FetchDescriptor<PendingOperation>(
                predicate: #Predicate { $0.blockedAt == nil },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            return try modelContext.fetch(ready).compactMap { operation in
                guard let type = PendingOperationType(rawValue: operation.operationType) else {
                    return nil
                }
                return PendingOperationSnapshot(
                    id: operation.id,
                    type: type,
                    mangaID: operation.mangaID,
                    payload: operation.payload,
                    attempts: operation.attempts
                )
            }
        }
    }

    /// Deletes a sent operation. An id that is gone (the operation was replaced while it was in
    /// flight) is ignored, so the replacement stays queued.
    func markOperationCompleted(id: UUID) throws(PersistenceError) {
        try run {
            guard let operation = try fetchOne(#Predicate<PendingOperation> { $0.id == id }) else {
                return
            }
            modelContext.delete(operation)
            try save()
        }
    }

    /// Records a failed send and blocks the operation once it reaches `maxAttempts`. Returns
    /// whether it is blocked now; an id that is gone is ignored and reports `false`.
    func markOperationFailed(id: UUID, error: String, maxAttempts: Int = 3, now: Date = .now) throws(PersistenceError) -> Bool {
        try run {
            guard let operation = try fetchOne(#Predicate<PendingOperation> { $0.id == id }) else {
                return false
            }
            operation.attempts += 1
            operation.lastError = error
            if operation.attempts >= maxAttempts {
                operation.blockedAt = now
            }
            try save()
            return operation.blockedAt != nil
        }
    }

    /// Gives every blocked operation a fresh start: back in the drain with no attempts or error.
    func unblockAll() throws(PersistenceError) {
        try run {
            let blocked = try modelContext.fetch(
                FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.blockedAt != nil })
            )
            for operation in blocked {
                operation.blockedAt = nil
                operation.attempts = 0
                operation.lastError = nil
            }
            try save()
        }
    }

    /// Every manga with a queued operation, blocked ones included: a local intention that has not
    /// reached the server must not be overwritten by it.
    func pendingMangaIDs() throws(PersistenceError) -> Set<Int> {
        try run {
            Set(try modelContext.fetch(FetchDescriptor<PendingOperation>()).map(\.mangaID))
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

    /// The first model matching `predicate`, fetching one row at most.
    func fetchOne<T: PersistentModel>(_ predicate: Predicate<T>) throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Upserts one manga and its authors, stamped with `now`, and returns the stored manga.
    func upsertManga(_ dto: MangaDTO, now: Date) throws -> Manga {
        let authors = try upsertAuthors(dto.authors)
        guard let manga = try upsertMangas([dto], authors: authors, now: now)[dto.id] else {
            preconditionFailure("upsertMangas returns every manga it is given")
        }
        return manga
    }

    /// Creates or updates the entry of `manga`, looked up by manga id so a manga never gets two,
    /// and puts the manga in the collection. Volumes are stored ascending and without duplicates.
    /// `updatedAt` moves only when the user fields change, so a snapshot that repeats what is
    /// stored never looks like a fresh edit.
    @discardableResult
    func applyEntry(
        to manga: Manga,
        volumesOwned: [Int],
        readingVolume: Int?,
        completeCollection: Bool,
        now: Date
    ) throws -> UserCollectionEntry {
        let mangaID = manga.id
        // Whatever the caller passes, the form or the server: volumes within 1…limit, and a
        // reading volume of 0 or below means none.
        let limit = UserCollectionEntry.volumeLimit
        let volumes = Set(volumesOwned.filter { (1 ... limit).contains($0) }).sorted()
        let readingVolume = readingVolume.flatMap { $0 > 0 ? min($0, limit) : nil }
        let entry: UserCollectionEntry
        if let existing = try fetchOne(#Predicate<UserCollectionEntry> { $0.mangaID == mangaID }) {
            entry = existing
        } else {
            entry = UserCollectionEntry(mangaID: mangaID, createdAt: now, updatedAt: now)
            modelContext.insert(entry)
        }
        let isChanged = entry.volumesOwned != volumes
            || entry.readingVolume != readingVolume
            || entry.completeCollection != completeCollection
            || !manga.inCollection
        if isChanged {
            entry.volumesOwned = volumes
            entry.readingVolume = readingVolume
            entry.completeCollection = completeCollection
            entry.updatedAt = now
            manga.updatedAt = now
        }
        entry.manga = manga
        manga.inCollection = true
        return entry
    }

    /// Queues a write for the server. At most one operation per manga: the new one replaces any
    /// earlier one, since only the last intention matters, and goes to the back of the queue.
    func replacePendingOperation(
        _ type: PendingOperationType,
        mangaID: Int,
        payload: Data?,
        now: Date
    ) throws {
        let previous = try modelContext.fetch(
            FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.mangaID == mangaID })
        )
        for operation in previous {
            modelContext.delete(operation)
        }
        modelContext.insert(PendingOperation(operationType: type, mangaID: mangaID, payload: payload, createdAt: now))
    }
}
