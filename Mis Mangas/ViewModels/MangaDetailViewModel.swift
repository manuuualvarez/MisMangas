//
//  MangaDetailViewModel.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
import Observation

/// Control state of the detail refresh: whether a refresh is in flight and the last error.
/// It never holds the manga: the detail reads it from the store, which `MangaSyncService` writes.
@Observable
@MainActor
final class MangaDetailViewModel {
    private let syncService: MangaSyncService
    private(set) var isRefreshing = false
    /// The last failed refresh; cleared by the next one that succeeds. Cancellation is not a failure.
    private(set) var refreshError: APIError?
    /// How long a cached manga outside the collection stays fresh.
    let cacheTTL: TimeInterval = 24 * 60 * 60

    init(syncService: MangaSyncService) {
        self.syncService = syncService
    }

    /// Asks the server again only when the cached record is stale: never cached, or cached
    /// longer than `cacheTTL` ago. A manga in the collection never goes stale.
    func refreshIfNeeded(manga: Manga) async {
        guard !manga.inCollection else {
            return
        }
        if let cachedAt = manga.cachedAt, Date.now.timeIntervalSince(cachedAt) < cacheTTL {
            return
        }
        await refresh(manga: manga)
    }

    /// Asks the server for the full record whatever its age, as the refresh button does. Skipped
    /// while another refresh is in flight: no second request.
    func refresh(manga: Manga) async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await syncService.refreshDetail(mangaID: manga.id)
            refreshError = nil
        } catch .cancelled {
            // The screen went away or moved on: nothing failed.
        } catch {
            refreshError = error
        }
    }
}
