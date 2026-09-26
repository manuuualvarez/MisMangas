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

    /// Whether the store holds the manga `id`, whatever brought it there.
    func hasManga(id: Int) throws(PersistenceError) -> Bool {
        try run {
            var descriptor = FetchDescriptor<Manga>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try modelContext.fetchCount(descriptor) > 0
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
    /// and the pending operation are always written together. The operation keeps `account`, the
    /// session the change was made in (`nil` as a guest). Throws `.notFound` when the manga is
    /// not stored: an entry always hangs from its manga.
    func saveCollectionEntry(
        mangaID: Int,
        volumesOwned: [Int],
        readingVolume: Int?,
        completeCollection: Bool,
        account: String?,
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
            try replacePendingOperation(.upsert, mangaID: mangaID, payload: payload, account: account, now: now)
            try save()
            return true
        }
        guard isStored else {
            throw .notFound
        }
    }

    /// Removes the entry of `mangaID`, takes the manga out of the collection and queues the
    /// deletion, in one transaction, under `account` like a save. The manga stays cached. The
    /// deletion is queued even without a local entry: the server may still hold one.
    func removeCollectionEntry(mangaID: Int, account: String?, now: Date = .now) throws(PersistenceError) {
        try run {
            if let entry = try fetchOne(#Predicate<UserCollectionEntry> { $0.mangaID == mangaID }) {
                modelContext.delete(entry)
            }
            if let manga = try fetchOne(#Predicate<Manga> { $0.id == mangaID }), manga.inCollection {
                manga.inCollection = false
                manga.updatedAt = now
            }
            try replacePendingOperation(.delete, mangaID: mangaID, payload: nil, account: account, now: now)
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

    /// The operations of `account` ready to send, oldest first; blocked ones wait for
    /// `unblockAll()`. Settles who owns the queue in the same transaction: the operations of
    /// another account are deleted, blocked ones included, since no other session may ever send
    /// them, and the ones made as a guest become `account`'s, since a guest's collection goes up
    /// with the first account that signs in. The operations stay stored until they are marked
    /// completed. A row whose type this version cannot read could never be sent, so it is deleted
    /// here instead of lingering in the queue.
    func drainPendingOperations(for account: String) throws(PersistenceError) -> [PendingOperationSnapshot] {
        try run {
            let queue = FetchDescriptor<PendingOperation>(sortBy: [SortDescriptor(\.createdAt)])
            var snapshots: [PendingOperationSnapshot] = []
            var hasChanges = false
            for operation in try modelContext.fetch(queue) {
                if let owner = operation.account, owner != account {
                    modelContext.delete(operation)
                    hasChanges = true
                    continue
                }
                guard let type = PendingOperationType(rawValue: operation.operationType) else {
                    modelContext.delete(operation)
                    hasChanges = true
                    continue
                }
                if operation.account == nil {
                    operation.account = account
                    hasChanges = true
                }
                guard operation.blockedAt == nil else {
                    continue
                }
                snapshots.append(PendingOperationSnapshot(
                    id: operation.id,
                    type: type,
                    mangaID: operation.mangaID,
                    payload: operation.payload,
                    attempts: operation.attempts
                ))
            }
            if hasChanges {
                try save()
            }
            return snapshots
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

    /// Queued operations still in the drain and blocked ones that the next pass of `account`
    /// would send: its own and the guest's. `nil` counts only the guest's.
    func pendingOperationCounts(for account: String?) throws(PersistenceError) -> (pending: Int, blocked: Int) {
        try run {
            let pending = try modelContext.fetchCount(FetchDescriptor<PendingOperation>(predicate: #Predicate {
                $0.blockedAt == nil && ($0.account == nil || $0.account == account)
            }))
            let blocked = try modelContext.fetchCount(FetchDescriptor<PendingOperation>(predicate: #Predicate {
                $0.blockedAt != nil && ($0.account == nil || $0.account == account)
            }))
            return (pending: pending, blocked: blocked)
        }
    }

    /// Leaves the device's collection to `account` when it signs in after another one, in one
    /// transaction: the changes of any other account are deleted, and so is every entry no change
    /// of `account` or of a guest still refers to (the previous account's collection), taking its
    /// manga out of the collection. A guest's changes stay, entries included, for the first pass to
    /// upload.
    func handOverCollection(to account: String, now: Date = .now) throws(PersistenceError) {
        try run {
            var kept = Set<Int>()
            for operation in try modelContext.fetch(FetchDescriptor<PendingOperation>()) {
                if let owner = operation.account, owner != account {
                    modelContext.delete(operation)
                } else {
                    kept.insert(operation.mangaID)
                }
            }
            for entry in try modelContext.fetch(FetchDescriptor<UserCollectionEntry>()) where !kept.contains(entry.mangaID) {
                if let manga = entry.manga, manga.inCollection {
                    manga.inCollection = false
                    manga.updatedAt = now
                }
                modelContext.delete(entry)
            }
            try save()
        }
    }

    /// Deletes every queued operation and leaves the entries as they are.
    func clearOutbox() throws(PersistenceError) {
        try run {
            try modelContext.delete(model: PendingOperation.self)
            try save()
        }
    }

    // MARK: - Watch reading list

    /// The mangas being read, most recently changed entry first, at most `limit` of them.
    func readingSnapshot(limit: Int, now: Date = .now) throws(PersistenceError) -> ReadingSnapshot {
        try run {
            // Ordered by the entry: the catalog also stamps the manga's own date.
            let entries = try modelContext.fetch(
                FetchDescriptor<UserCollectionEntry>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            )
            let items = entries.lazy
                .compactMap { entry -> ReadingItem? in
                    guard let manga = entry.manga, manga.isReading else {
                        return nil
                    }
                    return ReadingItem(
                        mangaID: manga.id,
                        title: manga.title,
                        coverURL: manga.mainPictureURL,
                        readingVolume: entry.readingVolume,
                        volumes: manga.volumes,
                        completeCollection: entry.completeCollection,
                        updatedAt: entry.updatedAt
                    )
                }
                .prefix(limit)
            return ReadingSnapshot(generatedAt: now, items: Array(items))
        }
    }

    /// Applies a reading volume chosen on the watch, in one transaction, when it was chosen after
    /// the entry's last change (`sentAt` later than `updatedAt`): the entry takes the volume and
    /// `sentAt` as its change date, and its upload is queued under `account`. Returns whether it
    /// applied; a repeated or older change, or a manga outside the collection, changes nothing.
    func applyReadingUpdate(mangaID: Int, readingVolume: Int, sentAt: Date, account: String?, now: Date = .now) throws(PersistenceError) -> Bool {
        try run {
            // Strictly later: the second copy of an update carries the date it already stamped.
            guard let entry = try fetchOne(#Predicate<UserCollectionEntry> { $0.mangaID == mangaID }),
                  let manga = entry.manga,
                  sentAt > entry.updatedAt else {
                return false
            }
            _ = try applyEntry(
                to: manga,
                volumesOwned: entry.volumesOwned,
                readingVolume: readingVolume,
                completeCollection: entry.completeCollection,
                now: sentAt
            )
            // Stamped with the watch's date even when the volume did not change, so the watch's
            // updates are ordered by a single clock.
            entry.updatedAt = sentAt
            manga.updatedAt = sentAt
            let payload = try JSONEncoder.app.encode(entry.toRequest())
            try replacePendingOperation(.upsert, mangaID: mangaID, payload: payload, account: account, now: now)
            try save()
            return true
        }
    }

    #if os(watchOS)
    /// Makes the watch's store match the reading list the iPhone published, in one transaction:
    /// every item is created or updated, and every manga the list no longer has is deleted. An
    /// entry the watch changed after the item's date keeps its volume; the rest is refreshed.
    func applyReadingSnapshot(_ snapshot: ReadingSnapshot) throws(PersistenceError) {
        try run {
            let listed = Set(snapshot.items.map(\.mangaID))
            // The watch keeps nothing but the reading list: a manga it no longer lists goes, and
            // its entry with it.
            for manga in try modelContext.fetch(FetchDescriptor<Manga>()) where !listed.contains(manga.id) {
                modelContext.delete(manga)
            }
            for item in snapshot.items {
                let mangaID = item.mangaID
                let manga: Manga
                if let stored = try fetchOne(#Predicate<Manga> { $0.id == mangaID }) {
                    manga = stored
                } else {
                    manga = Manga(id: mangaID, title: item.title, status: MangaStatus.none.rawValue, score: 0)
                    modelContext.insert(manga)
                }
                manga.title = item.title
                manga.mainPictureURL = item.coverURL
                manga.volumes = item.volumes
                manga.inCollection = true
                let entry: UserCollectionEntry
                if let stored = try fetchOne(#Predicate<UserCollectionEntry> { $0.mangaID == mangaID }) {
                    entry = stored
                } else {
                    entry = UserCollectionEntry(mangaID: mangaID, createdAt: item.updatedAt, updatedAt: item.updatedAt)
                    modelContext.insert(entry)
                }
                entry.manga = manga
                // A list the iPhone published before it received the watch's latest change would
                // undo it: the watch's own later change stays until a list that includes it comes.
                guard entry.updatedAt <= item.updatedAt else {
                    continue
                }
                manga.updatedAt = item.updatedAt
                entry.readingVolume = item.readingVolume
                entry.completeCollection = item.completeCollection
                entry.updatedAt = item.updatedAt
            }
            try save()
        }
    }

    /// Changes the reading volume on the watch, without queueing anything: the watch has no
    /// server. Returns the change date, which travels as the update's `sentAt`.
    func applyLocalReadingVolume(mangaID: Int, readingVolume: Int, now: Date = .now) throws(PersistenceError) -> Date {
        let isStored = try run {
            guard let entry = try fetchOne(#Predicate<UserCollectionEntry> { $0.mangaID == mangaID }),
                  let manga = entry.manga else {
                return false
            }
            _ = try applyEntry(
                to: manga,
                volumesOwned: entry.volumesOwned,
                readingVolume: readingVolume,
                completeCollection: entry.completeCollection,
                now: now
            )
            // Stamped even when the volume did not change: the date travels as the change's own.
            entry.updatedAt = now
            manga.updatedAt = now
            try save()
            return true
        }
        guard isStored else {
            throw .notFound
        }
        return now
    }
    #endif

    // MARK: - Server snapshot

    /// Makes the collection match the server's, in one transaction, except for the mangas with a
    /// queued operation (blocked ones included), whose local intention wins. Upserts every other
    /// entry with its nested manga and removes every local entry the server no longer has,
    /// taking its manga out of the collection without queueing anything. An entry whose user
    /// fields did not change keeps its `updatedAt`. Returns how many entries were written and how
    /// many were removed: `upserted` counts only the entries created or whose user fields changed.
    /// Throws `.cancelled` without touching the store when the calling pass was already stopped.
    func applyRemoteSnapshot(_ dtos: [UserMangaCollectionDTO], now: Date = .now) throws(PersistenceError) -> (upserted: Int, removed: Int) {
        guard !Task.isCancelled else {
            throw .cancelled
        }
        return try run {
            let pending = Set(try modelContext.fetch(FetchDescriptor<PendingOperation>()).map(\.mangaID))
            let incoming = dtos.filter { !pending.contains($0.manga.id) }
            let authors = try upsertAuthors(incoming.flatMap(\.manga.authors))
            let mangas = try upsertMangas(incoming.map(\.manga), authors: authors, now: now)
            var upserted = 0
            for dto in incoming {
                guard let manga = mangas[dto.manga.id] else {
                    continue
                }
                let previousUpdate = manga.collectionEntry?.updatedAt
                let entry = try applyEntry(
                    to: manga,
                    volumesOwned: dto.volumesOwned,
                    readingVolume: dto.readingVolume,
                    completeCollection: dto.completeCollection,
                    now: now
                )
                // `applyEntry` stamps `updatedAt` only when it creates the entry or changes it.
                if entry.updatedAt != previousUpdate {
                    upserted += 1
                }
            }
            let remoteIDs = Set(dtos.map(\.manga.id))
            var removed = 0
            for entry in try modelContext.fetch(FetchDescriptor<UserCollectionEntry>())
            where !remoteIDs.contains(entry.mangaID) && !pending.contains(entry.mangaID) {
                if let manga = entry.manga, manga.inCollection {
                    manga.inCollection = false
                    manga.updatedAt = now
                }
                modelContext.delete(entry)
                removed += 1
            }
            try save()
            return (upserted: upserted, removed: removed)
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

    /// Queues a write for the server under `account`. At most one operation per manga: the new
    /// one replaces any earlier one, owner included, since only the last intention matters, and
    /// goes to the back of the queue.
    func replacePendingOperation(
        _ type: PendingOperationType,
        mangaID: Int,
        payload: Data?,
        account: String?,
        now: Date
    ) throws {
        let previous = try modelContext.fetch(
            FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.mangaID == mangaID })
        )
        for operation in previous {
            modelContext.delete(operation)
        }
        modelContext.insert(PendingOperation(operationType: type, mangaID: mangaID, payload: payload, createdAt: now, account: account))
    }
}
