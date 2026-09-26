//
//  MangaSyncService.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// The one place where the network repositories meet the store: pulls catalog pages and hands
/// them to `MangaSyncActor`, and runs the collection's synchronization passes (the queued
/// changes up, the server collection down). Views then read the result through their queries.
/// It also serves the session's classification lists, which every screen shares through
/// `taxonomyCache`.
struct MangaSyncService {
    let syncActor: MangaSyncActor
    let mangaRepository: any MangaRepository
    /// The classification lists, loaded once per session for every screen built on this service.
    let taxonomyCache: TaxonomyCacheActor
    /// The user's collection on the server; `nil` for a guest, whose collection stays local.
    let collectionRepository: (any CollectionRepository)?
    /// The account whose queue the signed-in passes send; `nil` for a guest.
    let account: String?

    init(
        syncActor: MangaSyncActor,
        mangaRepository: any MangaRepository,
        taxonomyCache: TaxonomyCacheActor,
        collectionRepository: (any CollectionRepository)? = nil,
        account: String? = nil
    ) {
        self.syncActor = syncActor
        self.mangaRepository = mangaRepository
        self.taxonomyCache = taxonomyCache
        self.collectionRepository = collectionRepository
        self.account = account
    }

    /// Retention of index rows and unreferenced detail records.
    static let retentionWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Fetches one page of `mode` and stores it under `mode.modeKey`. Returns how many items
    /// arrived (so the caller can tell whether a next page exists) and the server total (for the
    /// header and the page count). A task cancelled before the page is stored ends as
    /// `APIError.cancelled` with the store untouched; other store failures surface as
    /// `APIError.unknown`.
    @discardableResult
    func loadCatalogPage(mode: CatalogMode, page: Int, per: Int) async throws(APIError) -> (received: Int, total: Int) {
        let pageDTO: MangaPageDTO
        switch mode {
        case .all:
            pageDTO = try await mangaRepository.fetchMangas(page: page, per: per)
        case .best:
            pageDTO = try await mangaRepository.fetchBestMangas(page: page, per: per)
        case .byGenre(let genre):
            pageDTO = try await mangaRepository.fetchMangasByGenre(genre, page: page, per: per)
        case .byTheme(let theme):
            pageDTO = try await mangaRepository.fetchMangasByTheme(theme, page: page, per: per)
        case .byDemographic(let demographic):
            pageDTO = try await mangaRepository.fetchMangasByDemographic(demographic, page: page, per: per)
        case .byAuthor(let id, _):
            pageDTO = try await mangaRepository.fetchMangasByAuthor(id, page: page, per: per)
        case .titleContains(let query):
            pageDTO = try await mangaRepository.searchContains(query, page: page, per: per)
        case .beginsWith(let query):
            // Not paginated by the server: the first `per` items are the whole result.
            let items = Array(try await mangaRepository.searchBeginsWith(query).prefix(per))
            pageDTO = MangaPageDTO(metadata: PageMetadataDTO(total: items.count, page: page, per: per), items: items)
        case .search(let search):
            pageDTO = try await mangaRepository.customSearch(search, page: page, per: per)
        }
        do {
            try await syncActor.replaceCatalogPage(modeKey: mode.modeKey, page: page, per: per, dtos: pageDTO.items)
        } catch .cancelled {
            // Cancelled while the page was in flight or waiting for the actor: the store kept what it had.
            throw .cancelled
        } catch {
            throw .unknown
        }
        return (received: pageDTO.items.count, total: pageDTO.metadata.total)
    }

    /// How many index rows `mode` holds right now, so a screen can tell whether the pages it
    /// loaded are still indexed. A store failure reports 0, which asks for a reload: erring
    /// towards loading again is the safe side.
    func indexedCount(mode: CatalogMode) async -> Int {
        (try? await syncActor.indexedCount(modeKey: mode.modeKey)) ?? 0
    }

    /// The genre, theme and demographic lists of the session, each requested once for every
    /// screen built on this service, and the error of the first list that failed, if any.
    func loadTaxonomies() async -> (catalog: TaxonomyCatalog, error: APIError?) {
        await taxonomyCache.load()
    }

    // MARK: - Detail and collection

    /// Stores a manga that arrived outside any catalog page (a deep link, a refreshed detail)
    /// and returns its id.
    @discardableResult
    func cacheDetail(_ dto: MangaDTO) async throws(PersistenceError) -> Int {
        try await syncActor.cacheDetail(dto)
    }

    /// Asks the server for the full record of `mangaID` and stores it. Store failures surface as
    /// `APIError.unknown`.
    func refreshDetail(mangaID: Int) async throws(APIError) {
        let dto = try await mangaRepository.fetchManga(id: mangaID)
        do {
            try await cacheDetail(dto)
        } catch {
            throw .unknown
        }
    }

    /// Saves the entry locally and queues its upload; the actor does both in one transaction.
    func saveCollectionEntry(
        mangaID: Int,
        volumesOwned: [Int],
        readingVolume: Int?,
        completeCollection: Bool,
        account: String?
    ) async throws(PersistenceError) {
        try await syncActor.saveCollectionEntry(
            mangaID: mangaID,
            volumesOwned: volumesOwned,
            readingVolume: readingVolume,
            completeCollection: completeCollection,
            account: account
        )
    }

    /// Removes the entry locally and queues its deletion; the actor does both in one transaction.
    func removeCollectionEntry(mangaID: Int, account: String?) async throws(PersistenceError) {
        try await syncActor.removeCollectionEntry(mangaID: mangaID, account: account)
    }

    /// One synchronization pass: sends the queued operations oldest first, then applies the
    /// server collection to the store. A guest gets an empty result without touching the network
    /// or the queue.
    ///
    /// Per operation: accepted → removed from the queue; transport or server failure → retried on
    /// a later pass and blocked at the third attempt; 401/403 → `.sessionExpired`, leaving the
    /// rest of the queue untouched; cancelled → the pass stops without marking it; a delete the
    /// server no longer had → applied; any other refusal → discarded and reported in `rejected`.
    func synchronizeCollection() async throws(SyncError) -> SyncResult {
        guard let collectionRepository, let account else {
            return SyncResult(applied: 0, blocked: 0, rejected: [], upserted: 0, removed: 0)
        }
        var applied = 0
        var blocked = 0
        var rejected: [Int] = []
        for operation in try await persistence({ () throws(PersistenceError) in try await syncActor.drainPendingOperations(for: account) }) {
            // A stopped pass sends nothing more: the session may be changing hands.
            guard !Task.isCancelled else {
                return SyncResult(applied: applied, blocked: blocked, rejected: rejected, upserted: 0, removed: 0)
            }
            let outcome = await send(operation, to: collectionRepository)
            switch outcome {
            case .applied:
                try await persistence { () throws(PersistenceError) in try await syncActor.markOperationCompleted(id: operation.id) }
                applied += 1
            case .retry(let category):
                let isBlocked = try await persistence { () throws(PersistenceError) in
                    try await syncActor.markOperationFailed(id: operation.id, error: category.rawValue)
                }
                if isBlocked {
                    blocked += 1
                }
            case .rejected:
                try await persistence { () throws(PersistenceError) in try await syncActor.markOperationCompleted(id: operation.id) }
                rejected.append(operation.mangaID)
            case .sessionExpired:
                throw .sessionExpired
            case .cancelled:
                return SyncResult(applied: applied, blocked: blocked, rejected: rejected, upserted: 0, removed: 0)
            }
        }
        let remote: [UserMangaCollectionDTO]
        do {
            remote = try await collectionRepository.fetchCollection()
        } catch {
            switch error {
            case .unauthorized, .forbidden:
                throw .sessionExpired
            default:
                // The queue is already sent; the snapshot waits for the next pass.
                return SyncResult(applied: applied, blocked: blocked, rejected: rejected, upserted: 0, removed: 0)
            }
        }
        guard !Task.isCancelled else {
            return SyncResult(applied: applied, blocked: blocked, rejected: rejected, upserted: 0, removed: 0)
        }
        let snapshot = try await persistence { () throws(PersistenceError) in
            try await syncActor.applyRemoteSnapshot(remote)
        }
        return SyncResult(applied: applied, blocked: blocked, rejected: rejected, upserted: snapshot.upserted, removed: snapshot.removed)
    }

    /// Whether passes reach the server: a signed-in account with its repository.
    var isSignedIn: Bool {
        collectionRepository != nil && account != nil
    }

    /// The queued changes of this service's account and the guest's, waiting and blocked.
    func pendingOperationCounts() async throws(PersistenceError) -> (pending: Int, blocked: Int) {
        try await syncActor.pendingOperationCounts(for: account)
    }

    /// Gives every blocked change a fresh start in the queue.
    func unblockAll() async throws(PersistenceError) {
        try await syncActor.unblockAll()
    }

    /// Author suggestions for the catalog filters, straight from the backend.
    func searchAuthors(_ query: String) async throws(APIError) -> [AuthorDTO] {
        try await mangaRepository.searchAuthors(query)
    }

    /// Start-up maintenance: purges the index first, then the detail records nothing references
    /// any more. Never throws: a failed purge only postpones the cleanup.
    func bootstrap() async -> (catalog: Int, details: Int) {
        let catalog = (try? await syncActor.purgeExpiredCatalog(olderThan: Self.retentionWindow)) ?? 0
        let details = (try? await syncActor.purgeExpiredDetailCache(olderThan: Self.retentionWindow)) ?? 0
        return (catalog, details)
    }
}

// MARK: - Synchronization helpers

private extension MangaSyncService {
    /// The only text a failed operation keeps in `lastError`: never a description, a body or a URL.
    enum RetryCategory: String {
        case transport
        case server
    }

    /// What sending one queued operation meant for the queue.
    enum SendOutcome {
        case applied
        /// Transient failure, recorded only by its category.
        case retry(RetryCategory)
        case rejected
        case sessionExpired
        case cancelled
    }

    func send(_ operation: PendingOperationSnapshot, to repository: any CollectionRepository) async -> SendOutcome {
        do {
            switch operation.type {
            case .upsert:
                guard let payload = operation.payload,
                      let request = try? JSONDecoder.app.decode(UserMangaCollectionRequest.self, from: payload) else {
                    return .rejected
                }
                try await repository.upsert(request)
            case .delete:
                try await repository.delete(mangaID: operation.mangaID)
            }
            return .applied
        } catch {
            switch error {
            case .unauthorized, .forbidden:
                return .sessionExpired
            case .cancelled:
                return .cancelled
            case .notFound where operation.type == .delete:
                return .applied
            case .transport:
                return .retry(.transport)
            default:
                return error.isRetryable ? .retry(.server) : .rejected
            }
        }
    }

    /// Runs a store call and reports its failure as `SyncError.persistence`.
    func persistence<T>(_ body: () async throws(PersistenceError) -> T) async throws(SyncError) -> T {
        do {
            return try await body()
        } catch {
            throw .persistence(error)
        }
    }
}
