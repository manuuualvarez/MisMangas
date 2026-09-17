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
/// Filters, title and author search and the advanced search form drive the same state: their
/// results are just other modes of the index.
@Observable
@MainActor
final class CatalogViewModel {
    private(set) var currentMode: CatalogMode
    private(set) var currentPage = 0
    private(set) var hasNextPage = true
    /// `metadata.total` of the last successful page; `nil` until one arrives.
    private(set) var totalCount: Int?
    /// Pages of `perPage` needed for `totalCount`; `nil` until one arrives.
    private(set) var totalPages: Int?
    private(set) var isLoading = false
    private(set) var loadError: APIError?
    let perPage = 20

    // MARK: Filters

    /// The three classification lists; `nil` until the first load. A list that failed stays
    /// empty until the next `loadTaxonomies()`.
    private(set) var taxonomies: TaxonomyCatalog?
    /// The error of a list that failed to load; `nil` once every list has arrived.
    private(set) var taxonomyError: APIError?

    // MARK: Search

    var searchText = ""
    var searchScope: SearchScope = .titles
    /// Index key of the suggestions on screen (`"begins:<text>"`); `nil` with fewer than three
    /// characters typed or after submitting the field.
    private(set) var suggestionsKey: String?
    private(set) var authorQuery = ""
    private(set) var authorResults: [AuthorDTO] = []
    /// The failure of the last suggestions or author request; `nil` once a later one succeeds
    /// or the field drops below its minimum. A cancellation is not a failure and never lands here.
    private(set) var searchError: APIError?
    /// The advanced search form, kept for the whole session so it reopens as it was left.
    var searchDraft: CustomSearch = .empty

    /// How many title suggestions are kept.
    private static let suggestionLimit = 8
    /// Pause after the last key stroke before a suggestions or author request goes out.
    private static let debounce: Duration = .milliseconds(300)
    private static let minimumTitleQuery = 3
    private static let minimumAuthorQuery = 2

    private let syncService: MangaSyncService
    @ObservationIgnored
    private var currentTask: Task<Void, Never>?
    /// The page of the last request, successful or not; `retry()` asks for it again.
    @ObservationIgnored
    private var lastRequestedPage = 1
    @ObservationIgnored
    private var taxonomyTask: Task<Void, Never>?
    /// The pending suggestions request, if any; awaiting it is how a caller learns it settled.
    @ObservationIgnored
    private(set) var suggestionsTask: Task<Void, Never>?
    /// The pending author search, if any.
    @ObservationIgnored
    private(set) var authorTask: Task<Void, Never>?

    init(syncService: MangaSyncService, mode: CatalogMode = .all) {
        self.syncService = syncService
        currentMode = mode
    }

    /// Loads page 1 of `mode`, replacing the mode's index only if the download succeeds. A load
    /// still in flight is cancelled first, so its late result never reaches the store or this
    /// state. Every failure lands in `loadError` and leaves the store as it was. The work runs
    /// in its own task: cancelling the caller (a view's `.task` going away) does not abort it.
    func loadInitial(mode: CatalogMode) async {
        currentTask?.cancel()
        if mode != currentMode {
            // The header total belongs to the mode that produced it; a refresh keeps it.
            totalCount = nil
            totalPages = nil
        }
        currentMode = mode
        await run(mode: mode, page: 1)
    }

    /// Loads the page after `currentPage`. Does nothing while a load is in flight or when the
    /// last page was already short. A failed page keeps `hasNextPage`, so a retry asks for it again.
    func loadMore() async {
        guard !isLoading, hasNextPage else {
            return
        }
        await run(mode: currentMode, page: currentPage + 1)
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
        await run(mode: currentMode, page: lastRequestedPage)
    }

    /// Back to the whole catalog, cancelling whatever filter was loading.
    func clearFilter() async {
        await loadInitial(mode: .all)
    }

    // MARK: - Taxonomies

    /// Loads the lists that are still missing, the three in parallel on the first call. A list
    /// already loaded is never requested again, so a form can call this every time it opens;
    /// after a partial failure the next call retries only the lists that failed. A call that
    /// arrives while another is loading waits for it instead of requesting again.
    func loadTaxonomies() async {
        if let taxonomyTask {
            await taxonomyTask.value
            return
        }
        let current = taxonomies ?? .empty
        guard current.genres.isEmpty || current.themes.isEmpty || current.demographics.isEmpty else {
            return
        }
        let task = Task { await fetchMissingTaxonomies(from: current) }
        taxonomyTask = task
        await task.value
        taxonomyTask = nil
    }

    private func fetchMissingTaxonomies(from current: TaxonomyCatalog) async {
        let repository = syncService.mangaRepository
        // The closures spell their error type: a bare `try` would be inferred as untyped.
        async let genres = Self.list(current.genres) { () async throws(APIError) in
            try await repository.fetchAllGenres()
        }
        async let themes = Self.list(current.themes) { () async throws(APIError) in
            try await repository.fetchAllThemes()
        }
        async let demographics = Self.list(current.demographics) { () async throws(APIError) in
            try await repository.fetchAllDemographics()
        }
        let loaded = await (genres, themes, demographics)
        taxonomies = TaxonomyCatalog(
            genres: Self.values(loaded.0),
            themes: Self.values(loaded.1),
            demographics: Self.values(loaded.2)
        )
        taxonomyError = [loaded.0, loaded.1, loaded.2].compactMap(Self.failure).first
    }

    // MARK: - Title search

    /// Called on every change of the search field. Fewer than three characters clear the
    /// suggestions without a request; from three on, a request goes out once the text has been
    /// still for the debounce. A newer key stroke cancels the pending one, and a cancelled
    /// request never writes its index nor changes the key, so only the last text survives.
    func updateSearchText(_ text: String) {
        suggestionsTask?.cancel()
        guard text.count >= Self.minimumTitleQuery else {
            suggestionsTask = nil
            suggestionsKey = nil
            searchError = nil
            return
        }
        suggestionsTask = Task {
            guard await Self.debounceElapsed() else {
                return
            }
            let mode = CatalogMode.beginsWith(text)
            do throws(APIError) {
                try await syncService.loadCatalogPage(mode: mode, page: 1, per: Self.suggestionLimit)
            } catch {
                // Cancelled mid-flight: a newer key stroke owns the field now.
                guard !Task.isCancelled else {
                    return
                }
                searchError = error
                return
            }
            guard !Task.isCancelled else {
                return
            }
            searchError = nil
            suggestionsKey = mode.modeKey
        }
    }

    /// Sends the field as a title search: a paginated mode that replaces the catalog on screen.
    /// The suggestions are dismissed. An empty field submits nothing.
    func submitSearch() async {
        suggestionsTask?.cancel()
        suggestionsKey = nil
        guard !searchText.isEmpty else {
            return
        }
        await loadInitial(mode: .titleContains(searchText))
    }

    // MARK: - Authors

    /// Same debounce as the titles, from two characters on. Fewer characters clear the results.
    func searchAuthors(_ query: String) {
        authorTask?.cancel()
        authorQuery = query
        guard query.count >= Self.minimumAuthorQuery else {
            authorTask = nil
            authorResults = []
            searchError = nil
            return
        }
        let repository = syncService.mangaRepository
        authorTask = Task {
            guard await Self.debounceElapsed() else {
                return
            }
            let results: [AuthorDTO]
            do throws(APIError) {
                results = try await repository.searchAuthors(query)
            } catch {
                // Cancelled mid-flight: a newer key stroke owns the field now.
                guard !Task.isCancelled else {
                    return
                }
                searchError = error
                return
            }
            guard !Task.isCancelled else {
                return
            }
            searchError = nil
            authorResults = results
        }
    }

    /// Lists the works of `author`, titled with the name as the backend spells it.
    func select(author: AuthorDTO) async {
        let name = [author.firstName, author.lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        await loadInitial(mode: .byAuthor(id: author.id, name: name))
    }

    // MARK: - Advanced search

    /// Runs the form as it stands; the draft itself is kept.
    func applyAdvancedSearch() async {
        await loadInitial(mode: .search(searchDraft.normalized))
    }

    func resetDraft() {
        searchDraft = .empty
    }

    // MARK: - Private

    /// Waits out the debounce. `false` when a newer key stroke cancelled the wait, the only
    /// reason the sleep can end early.
    private static func debounceElapsed() async -> Bool {
        do {
            try await Task.sleep(for: debounce)
            return true
        } catch {
            return false
        }
    }

    /// Marks the load as in flight before any suspension, so a call queued behind this one sees
    /// `isLoading` already set, then runs it in its own task and waits for it. The mode travels
    /// with the page: the request is fixed here, not when the task gets to run.
    private func run(mode: CatalogMode, page: Int) async {
        lastRequestedPage = page
        isLoading = true
        loadError = nil
        let task = Task { await load(mode: mode, page: page) }
        currentTask = task
        await task.value
    }

    private func load(mode: CatalogMode, page: Int) async {
        do {
            let result = try await syncService.loadCatalogPage(mode: mode, page: page, per: perPage)
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

    /// Keeps `existing` when it has content; otherwise runs `fetch` and captures its outcome.
    private nonisolated static func list(
        _ existing: [String],
        fetch: () async throws(APIError) -> [String]
    ) async -> Result<[String], APIError> {
        guard existing.isEmpty else {
            return .success(existing)
        }
        do throws(APIError) {
            return .success(try await fetch())
        } catch {
            return .failure(error)
        }
    }

    private static func values(_ result: Result<[String], APIError>) -> [String] {
        if case .success(let values) = result { values } else { [] }
    }

    private static func failure(_ result: Result<[String], APIError>) -> APIError? {
        if case .failure(let error) = result { error } else { nil }
    }
}
