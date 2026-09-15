//
//  CatalogViewModel.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Observation

/// Control state of the catalog screen: which mode is shown, which page is loaded, whether a
/// load is in flight and the last error. It never holds rows: the screen reads them from the
/// store with a query on the index of `currentMode`, which `MangaSyncService` fills.
@Observable
@MainActor
final class CatalogViewModel {
    private(set) var currentMode: CatalogMode = .all
    private(set) var currentPage = 0
    private(set) var hasNextPage = true
    /// `metadata.total` of the last successful page; `nil` until one arrives.
    private(set) var totalCount: Int?
    /// Pages of `perPage` needed for `totalCount`; `nil` until one arrives.
    private(set) var totalPages: Int?
    private(set) var isLoading = false
    private(set) var loadError: APIError?
    let perPage = 20

    private let syncService: MangaSyncService
    @ObservationIgnored
    private var currentTask: Task<Void, Never>?
    /// The page of the last request, successful or not; `retry()` asks for it again.
    @ObservationIgnored
    private var lastRequestedPage = 1

    init(syncService: MangaSyncService) {
        self.syncService = syncService
    }

    /// Loads page 1 of `mode`, replacing the mode's index only if the download succeeds. A load
    /// still in flight is cancelled first, so its late result never reaches the store or this
    /// state. Every failure lands in `loadError` and leaves the store as it was. The work runs
    /// in its own task: cancelling the caller (a view's `.task` going away) does not abort it.
    func loadInitial(mode: CatalogMode) async {
        currentTask?.cancel()
        currentMode = mode
        await run(page: 1)
    }

    /// Loads the page after `currentPage`. Does nothing while a load is in flight or when the
    /// last page was already short. A failed page keeps `hasNextPage`, so a retry asks for it again.
    func loadMore() async {
        guard !isLoading, hasNextPage else {
            return
        }
        await run(page: currentPage + 1)
    }

    /// Pull-to-refresh: page 1 of the current mode again.
    func refresh() async {
        await loadInitial(mode: currentMode)
    }

    /// Asks again for the page that failed, whether it was a refresh (page 1) or the next page.
    /// Does nothing while a load is in flight.
    func retry() async {
        guard !isLoading else {
            return
        }
        await run(page: lastRequestedPage)
    }

    /// Marks the load as in flight before any suspension, so a call queued behind this one sees
    /// `isLoading` already set, then runs it in its own task and waits for it.
    private func run(page: Int) async {
        lastRequestedPage = page
        isLoading = true
        loadError = nil
        let task = Task { await load(page: page) }
        currentTask = task
        await task.value
    }

    private func load(page: Int) async {
        do {
            let result = try await syncService.loadCatalogPage(mode: currentMode, page: page, per: perPage)
            // Cancelled after the download finished: a newer load owns the state now.
            guard !Task.isCancelled else {
                return
            }
            currentPage = page
            hasNextPage = result.received == perPage
            totalCount = result.total
            totalPages = (result.total + perPage - 1) / perPage
        } catch {
            guard !Task.isCancelled else {
                return
            }
            loadError = error
        }
        isLoading = false
    }
}
