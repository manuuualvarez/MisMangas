//
//  MangaSyncService.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// The one place where the network repository meets the store: pulls a catalog page and hands
/// it to `MangaSyncActor`. Views then read the result through their queries.
struct MangaSyncService {
    let syncActor: MangaSyncActor
    let mangaRepository: any MangaRepository

    /// Retention of index rows and unreferenced detail records.
    static let retentionWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Fetches one page of `mode` and stores it under `mode.modeKey`. Returns the number of
    /// items received, so the caller can tell whether a next page exists. Store failures
    /// surface as `APIError.unknown`.
    @discardableResult
    func loadCatalogPage(mode: CatalogMode, page: Int, per: Int) async throws(APIError) -> Int {
        let pageDTO: MangaPageDTO
        switch mode {
        case .all:
            pageDTO = try await mangaRepository.fetchMangas(page: page, per: per)
        case .best:
            pageDTO = try await mangaRepository.fetchBestMangas(page: page, per: per)
        }
        do {
            try await syncActor.replaceCatalogPage(modeKey: mode.modeKey, page: page, per: per, dtos: pageDTO.items)
        } catch {
            throw .unknown
        }
        return pageDTO.items.count
    }

    /// Start-up maintenance: purges the index first, then the detail records nothing references
    /// any more. Never throws: a failed purge only postpones the cleanup.
    func bootstrap() async -> (catalog: Int, details: Int) {
        let catalog = (try? await syncActor.purgeExpiredCatalog(olderThan: Self.retentionWindow)) ?? 0
        let details = (try? await syncActor.purgeExpiredDetailCache(olderThan: Self.retentionWindow)) ?? 0
        return (catalog, details)
    }
}
