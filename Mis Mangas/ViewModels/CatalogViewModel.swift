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

    /// `true` when a filtered mode failed because the server does not know its category (a 404):
    /// read as "no results" rather than as a failure, since asking again would not change it.
    var isModeNotFound: Bool {
        guard currentMode.isFiltered, case .notFound? = loadError else {
            return false
        }
        return true
    }

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
    /// `true` from the key stroke that starts an author request until its results or failure
    /// land, so a picker can tell "nothing yet" from "nothing found".
    private(set) var isSearchingAuthors = false
    /// The failure of the last suggestions or author request; `nil` once a later one succeeds
    /// or the field drops below its minimum. A cancellation is not a failure and never lands here.
    private(set) var searchError: APIError?
    /// Fields of the advanced search form, kept for the whole session so it reopens as it was
    /// left. The form binds to them directly.
    var draftTitle = ""
    var draftAuthorFirstName = ""
    var draftAuthorLastName = ""
    var draftGenres: Set<String> = []
    var draftThemes: Set<String> = []
    var draftDemographics: Set<String> = []
    var draftContains = false

    /// The form read as a search request. Every list keeps the order the server sent it in, so
    /// the same picks always produce the same body and the same index key; without the lists,
    /// alphabetical order. Strings travel untrimmed: `normalized` is what cleans them before
    /// they go on the wire.
    var searchDraft: CustomSearch {
        CustomSearch(
            searchTitle: draftTitle,
            searchAuthorFirstName: draftAuthorFirstName,
            searchAuthorLastName: draftAuthorLastName,
            searchGenres: ordered(draftGenres, as: taxonomies?.genres),
            searchThemes: ordered(draftThemes, as: taxonomies?.themes),
            searchDemographics: ordered(draftDemographics, as: taxonomies?.demographics),
            searchContains: draftContains
        )
    }

    /// Whether the form carries no criteria at all, so a screen can tell that there is nothing
    /// to clear. Blank fields and untouched lists do not count: what matters is what would
    /// travel to the server.
    var isDraftEmpty: Bool {
        searchDraft.normalized == .empty
    }

    /// Whether the field has asked for authors at all: below the minimum nothing was searched,
    /// so an empty result is "nothing typed yet" rather than "nothing found".
    var hasAuthorQuery: Bool {
        authorQuery.count >= Self.minimumAuthorQuery
    }

    /// How many title suggestions are kept.
    private static let suggestionLimit = 8
    /// Pause after the last key stroke before a suggestions or author request goes out.
    private static let debounce: Duration = .milliseconds(300)
    private static let minimumTitleQuery = 3
    /// Characters an author query needs before a request goes out; below it nothing was searched.
    private static let minimumAuthorQuery = 2

    private let syncService: MangaSyncService
    @ObservationIgnored
    private var currentTask: Task<Void, Never>?
    /// The page of the last request, successful or not; `retry()` asks for it again.
    @ObservationIgnored
    private var lastRequestedPage = 1
    /// The mode whose first page this screen holds; `nil` while it has none, so that showing the
    /// screen again asks for it. Only a first page changes it: a later page that fails leaves the
    /// pages already indexed alone.
    @ObservationIgnored
    private var loadedMode: CatalogMode?
    /// How many rows the last page this screen loaded leaves in the index: everything before that
    /// page plus what it brought. The index itself is shared, so this is only what this screen
    /// expects to find there.
    @ObservationIgnored
    private var loadedEntryCount = 0
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

    /// Loads `mode` unless this screen already loaded it and the index still holds those pages.
    /// Showing the screen again — coming back to a tab — must not ask for page 1 again: storing
    /// it replaces the mode's index, so the pages the reader had already scrolled through would
    /// vanish under them. But the index of a mode belongs to the whole app, and another screen
    /// loading its first page truncates it, which would leave this one paging on from a page
    /// that is no longer there and skipping everything in between. So the store decides, not
    /// this screen's memory. Pull to refresh still reloads on demand.
    func loadInitialIfNeeded(mode: CatalogMode) async {
        if loadedMode == mode {
            // Back on a mode this screen holds while another one was still loading: that load
            // belongs to a mode nobody shows any more, so it is dropped, and the state it would
            // have settled — the mode and the spinner that gates paging — is settled here. Before
            // asking the store: during that wait the dropped load could still land and take over
            // the page, the total and the loaded mode.
            if currentMode != mode {
                currentTask?.cancel()
                currentMode = mode
                isLoading = false
            }
            let expected = loadedEntryCount
            let indexed = await syncService.indexedCount(mode: mode)
            // A newer call owns the screen now: the view's task was replaced, or a load started.
            guard !Task.isCancelled, loadedMode == mode, currentMode == mode else {
                return
            }
            if indexed >= expected {
                return
            }
        }
        await loadInitial(mode: mode)
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

    // MARK: - Taxonomies

    /// Shows the session's lists, loading the ones still missing. The service requests each
    /// list once for the whole app, so a form can call this every time it opens; after a
    /// partial failure the next call retries only the lists that failed.
    func loadTaxonomies() async {
        let result = await syncService.loadTaxonomies()
        taxonomies = result.catalog
        taxonomyError = result.error
    }

    // MARK: - Search

    /// Sends the field to the request of the scope in force. Called on every change of the text
    /// and of the scope, so switching scope with text already typed searches it again in the
    /// new domain.
    func search(_ text: String) {
        switch searchScope {
        case .titles:
            updateSearchText(text)
        case .authors:
            searchAuthors(text)
        }
    }

    // MARK: - Title search

    /// Called on every change of the search field. Fewer than three characters clear the
    /// suggestions without a request; from three on, a request goes out once the text has been
    /// still for the debounce. A newer key stroke cancels the pending one, and a cancelled
    /// request never writes its index nor changes the key, so only the last text survives.
    func updateSearchText(_ text: String) {
        suggestionsTask?.cancel()
        // The failure on screen belongs to the text that produced it: a new request owns the
        // field from here on, whether it succeeds or not.
        searchError = nil
        guard text.count >= Self.minimumTitleQuery else {
            suggestionsTask = nil
            suggestionsKey = nil
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
    /// The suggestions are dismissed. An empty field submits nothing, and neither does the
    /// Authors scope, whose results are chosen from the rows of the matching authors.
    func submitSearch() async {
        suggestionsTask?.cancel()
        suggestionsKey = nil
        guard searchScope == .titles, !searchText.isEmpty else {
            return
        }
        await loadInitial(mode: .titleContains(searchText))
    }

    // MARK: - Authors

    /// Same debounce as the titles, from two characters on. Fewer characters clear the results.
    /// The request counts as in flight from this call until its outcome lands; a newer key
    /// stroke takes the flag over, so a cancelled request never clears it.
    func searchAuthors(_ query: String) {
        authorTask?.cancel()
        authorQuery = query
        // Same rule as the titles: the failure on screen belongs to the text that produced it.
        searchError = nil
        guard query.count >= Self.minimumAuthorQuery else {
            authorTask = nil
            authorResults = []
            isSearchingAuthors = false
            return
        }
        isSearchingAuthors = true
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
                isSearchingAuthors = false
                return
            }
            guard !Task.isCancelled else {
                return
            }
            searchError = nil
            authorResults = results
            isSearchingAuthors = false
        }
    }

    /// Lists the works of `author`, titled with the name as the backend spells it.
    func select(author: AuthorDTO) async {
        await loadInitial(mode: .byAuthor(id: author.id, name: author.displayName))
    }

    // MARK: - Advanced search

    /// Runs the form as it stands; the draft itself is kept.
    func applyAdvancedSearch() async {
        await loadInitial(mode: .search(searchDraft.normalized))
    }

    /// Returns every field of the form to its initial value.
    func resetDraft() {
        draftTitle = ""
        draftAuthorFirstName = ""
        draftAuthorLastName = ""
        draftGenres = []
        draftThemes = []
        draftDemographics = []
        draftContains = false
    }

    // MARK: - Private

    /// The picked values in the order of the list they came from, or alphabetical while that
    /// list is missing. A `Set` has no order of its own and its iteration changes between runs,
    /// which would change the body and the index key of the same search.
    private func ordered(_ picked: Set<String>, as list: [String]?) -> [String] {
        guard let list else { return picked.sorted() }
        return list.filter(picked.contains)
    }

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
            if page == 1 {
                loadedMode = mode
            }
            // The store replaces a page from its first ordinal on, so this is what it now holds.
            loadedEntryCount = (page - 1) * perPage + result.received
        } catch {
            guard !Task.isCancelled else {
                return
            }
            if page == 1 {
                // A new mode that never landed has no pages of its own: paging on from the
                // previous mode's page would index it with a gap. A failed refresh of the same
                // mode keeps its page, since those rows are still indexed.
                if loadedMode != mode {
                    currentPage = 0
                    hasNextPage = true
                }
                loadedMode = nil
                loadedEntryCount = 0
            }
            loadError = error
        }
        isLoading = false
    }
}
