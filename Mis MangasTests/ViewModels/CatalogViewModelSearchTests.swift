//
//  CatalogViewModelSearchTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 17/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// Filters, suggestions, author lookup and advanced search driven through the real pipeline:
    /// ViewModel → service → mocked transport → decode → `MangaSyncActor` → store. Oracles are
    /// the requests the mock captured (path, query, method, body), the content of the fixtures
    /// (counts, ids, names) and a fresh `ModelContext` read of the index each mode leaves behind.
    @Suite("CatalogViewModel search & filters")
    @MainActor
    struct CatalogViewModelSearchTests {
        private let viewModel: CatalogViewModel
        /// The service behind `viewModel`, for tests that open a second screen on the same session.
        private let service: MangaSyncService
        private let container: ModelContainer
        /// Page 1 of `/list/mangas`, reused as the answer of every paginated filter route.
        private let allPage: MangaPageDTO

        init() throws {
            CatalogMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            container = made.container
            let repository = DefaultMangaRepositoryTest()
            service = MangaSyncService(
                syncActor: made.actor,
                mangaRepository: repository,
                taxonomyCache: TaxonomyCacheActor(mangaRepository: repository)
            )
            viewModel = CatalogViewModel(syncService: service)
            allPage = try JSONDecoder.app.decode(MangaPageDTO.self, from: TestFixtures.data("mangas_page.json"))
        }

        // MARK: - Taxonomies

        @Test func `loadTaxonomies fetches the three lists once even when called three times`() async throws {
            CatalogMockScenario.set([
                .listGenres: .fixture("genres.json"),
                .listThemes: .fixture("themes.json"),
                .listDemographics: .fixture("demographics.json"),
            ])

            await viewModel.loadTaxonomies()
            await viewModel.loadTaxonomies()
            await viewModel.loadTaxonomies()

            #expect(CatalogMockScenario.hits(.listGenres) == 1)
            #expect(CatalogMockScenario.hits(.listThemes) == 1)
            #expect(CatalogMockScenario.hits(.listDemographics) == 1)
            let taxonomies = try #require(viewModel.taxonomies)
            #expect(taxonomies.genres.count == 21)
            #expect(taxonomies.themes.count == 52)
            #expect(taxonomies.themes.contains("Idols (Female)"))
            #expect(taxonomies.demographics == ["Seinen", "Shounen", "Shoujo", "Josei", "Kids"])
            #expect(viewModel.taxonomyError == nil)
        }

        @Test func `Two overlapping loadTaxonomies calls share one request per list`() async throws {
            CatalogMockScenario.set([
                .listGenres: .delayed(for: .milliseconds(200), then: .fixture("genres.json")),
                .listThemes: .delayed(for: .milliseconds(200), then: .fixture("themes.json")),
                .listDemographics: .delayed(for: .milliseconds(200), then: .fixture("demographics.json")),
            ])
            let viewModel = viewModel

            let first = Task { await viewModel.loadTaxonomies() }
            try await Task.sleep(for: .milliseconds(50))
            let second = Task { await viewModel.loadTaxonomies() }
            await first.value
            await second.value

            #expect(CatalogMockScenario.hits(.listGenres) == 1)
            #expect(CatalogMockScenario.hits(.listThemes) == 1)
            #expect(CatalogMockScenario.hits(.listDemographics) == 1)
            let taxonomies = try #require(viewModel.taxonomies)
            #expect(taxonomies.genres.count == 21)
            #expect(taxonomies.themes.count == 52)
            #expect(taxonomies.demographics.count == 5)
            #expect(viewModel.taxonomyError == nil)
        }

        @Test func `A failed themes list keeps the other two and a retry fetches only the themes again`() async throws {
            CatalogMockScenario.set([
                .listGenres: .fixture("genres.json"),
                .listThemes: .status(500),
                .listDemographics: .fixture("demographics.json"),
            ])

            await viewModel.loadTaxonomies()

            let error = try #require(viewModel.taxonomyError)
            expectAPIError(.serverError, matches: error)
            let partial = try #require(viewModel.taxonomies)
            #expect(partial.genres.count == 21)
            #expect(partial.demographics.count == 5)
            #expect(partial.themes.isEmpty)

            CatalogMockScenario.set(.listThemes, .fixture("themes.json"))
            await viewModel.loadTaxonomies()

            #expect(CatalogMockScenario.hits(.listGenres) == 1)
            #expect(CatalogMockScenario.hits(.listThemes) == 2)
            #expect(CatalogMockScenario.hits(.listDemographics) == 1)
            let complete = try #require(viewModel.taxonomies)
            #expect(complete.themes.count == 52)
            #expect(complete.genres.count == 21)
            #expect(viewModel.taxonomyError == nil)
        }

        @Test func `Two view models on the same service fetch each list once between them`() async throws {
            CatalogMockScenario.set([
                .listGenres: .fixture("genres.json"),
                .listThemes: .fixture("themes.json"),
                .listDemographics: .fixture("demographics.json"),
            ])
            let secondScreen = CatalogViewModel(syncService: service)

            await viewModel.loadTaxonomies()
            await secondScreen.loadTaxonomies()

            #expect(CatalogMockScenario.hits(.listGenres) == 1)
            #expect(CatalogMockScenario.hits(.listThemes) == 1)
            #expect(CatalogMockScenario.hits(.listDemographics) == 1)
            let first = try #require(viewModel.taxonomies)
            #expect(first.genres.count == 21)
            #expect(first.themes.count == 52)
            #expect(first.demographics.count == 5)
            #expect(viewModel.taxonomyError == nil)
            let second = try #require(secondScreen.taxonomies)
            #expect(second.genres.count == 21)
            #expect(second.themes.count == 52)
            #expect(second.demographics.count == 5)
            #expect(secondScreen.taxonomyError == nil)
        }

        @Test func `Cancelling the screen that started the load neither aborts it nor makes the next screen ask again`() async throws {
            CatalogMockScenario.set([
                .listGenres: .delayed(for: .milliseconds(200), then: .fixture("genres.json")),
                .listThemes: .delayed(for: .milliseconds(200), then: .fixture("themes.json")),
                .listDemographics: .delayed(for: .milliseconds(200), then: .fixture("demographics.json")),
            ])
            let viewModel = viewModel

            let leaving = Task { await viewModel.loadTaxonomies() }
            try await Task.sleep(for: .milliseconds(50))
            leaving.cancel()
            await leaving.value

            // The load it started outlives the screen: the lists reach it in full.
            let cancelledScreen = try #require(viewModel.taxonomies)
            #expect(cancelledScreen.genres.count == 21)
            #expect(cancelledScreen.themes.count == 52)
            #expect(cancelledScreen.demographics.count == 5)
            let nextScreen = CatalogViewModel(syncService: service)
            await nextScreen.loadTaxonomies()

            #expect(CatalogMockScenario.hits(.listGenres) == 1)
            #expect(CatalogMockScenario.hits(.listThemes) == 1)
            #expect(CatalogMockScenario.hits(.listDemographics) == 1)
            let taxonomies = try #require(nextScreen.taxonomies)
            #expect(taxonomies.genres.count == 21)
            #expect(taxonomies.themes.count == 52)
            #expect(taxonomies.demographics.count == 5)
            #expect(nextScreen.taxonomyError == nil)
        }

        // MARK: - Category filters

        @Test func `A category the server does not list reads as nothing found, not as a failure`() async throws {
            CatalogMockScenario.set(.mangaByGenre, .status(404))
            CatalogMockScenario.set(.listMangas, .status(404))

            await viewModel.loadInitial(mode: .byGenre("zzz"))

            let error = try #require(viewModel.loadError)
            expectAPIError(.notFound, matches: error)
            #expect(viewModel.isModeNotFound)

            await viewModel.loadInitial(mode: .all)

            try expectAPIError(.notFound, matches: #require(viewModel.loadError))
            #expect(!viewModel.isModeNotFound)
        }

        @Test func `loadInitial byGenre requests the genre route paginated and indexes the page under its key`() async throws {
            CatalogMockScenario.set(.mangaByGenre, .fixture("mangas_page.json"))

            await viewModel.loadInitial(mode: .byGenre("Romance"))

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByGenre))
            #expect(sent.path == "/list/mangaByGenre/Romance")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(CatalogMockScenario.hits(.mangaByGenre) == 1)
            #expect(CatalogMockScenario.hits(.listMangas) == 0)
            #expect(viewModel.currentMode.title == "Romance")
            #expect(viewModel.currentMode.isFiltered)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.loadError == nil)
            #expect(!viewModel.isLoading)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "genre:Romance", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == allPage.items.map(\.id))
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).isEmpty)
        }

        @Test func `loadInitial byTheme percent-encodes the theme in the path and indexes under the theme key`() async throws {
            CatalogMockScenario.set(.mangaByTheme, .fixture("mangas_page.json"))

            await viewModel.loadInitial(mode: .byTheme("Martial Arts"))

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByTheme))
            #expect(sent.path == "/list/mangaByTheme/Martial Arts")
            let url = try #require(sent.request.url)
            #expect(url.absoluteString.contains("Martial%20Arts"))
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(viewModel.currentMode.title == "Martial Arts")
            #expect(viewModel.currentMode.isFiltered)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "theme:Martial Arts", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == allPage.items.map(\.id))
        }

        @Test func `loadInitial byDemographic requests the demographic route and indexes under the demographic key`() async throws {
            CatalogMockScenario.set(.mangaByDemographic, .fixture("mangas_page.json"))

            await viewModel.loadInitial(mode: .byDemographic("Shounen"))

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByDemographic))
            #expect(sent.path == "/list/mangaByDemographic/Shounen")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(viewModel.currentMode.title == "Shounen")
            #expect(viewModel.currentMode.isFiltered)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "demographic:Shounen", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == allPage.items.map(\.id))
        }

        @Test func `loadInitial byAuthor requests the author route by id and shows the author name`() async throws {
            CatalogMockScenario.set(.mangaByAuthor, .fixture("mangas_page.json"))
            let authorID = try #require(UUID(uuidString: "998C1B16-E3DB-47D1-8157-8389B5345D03"))

            await viewModel.loadInitial(mode: .byAuthor(id: authorID, name: "Akira Toriyama"))

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByAuthor))
            let path = try #require(sent.path)
            #expect(path.lowercased() == "/list/mangaByAuthor/\(authorID.uuidString)".lowercased())
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(viewModel.currentMode.title == "Akira Toriyama")
            #expect(viewModel.currentMode.isFiltered)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "author:\(authorID.uuidString)", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == allPage.items.map(\.id))
        }

        @Test func `loadMore on a genre filter requests page 2 of the same route and appends 20 entries`() async throws {
            CatalogMockScenario.set(.mangaByGenre, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .byGenre("Romance"))
            let page2 = allPage.items.shiftingIDs(by: 100_000)
            try CatalogMockScenario.set(.mangaByGenre, .data(encodedPage(page2, page: 2)))

            await viewModel.loadMore()

            let requests = CatalogMockScenario.requests(.mangaByGenre)
            #expect(requests.count == 2)
            #expect(requests.last?.path == "/list/mangaByGenre/Romance")
            #expect(requests.last?.queryValues == ["page": "2", "per": "20"])
            #expect(viewModel.currentMode == .byGenre("Romance"))
            #expect(viewModel.currentPage == 2)
            #expect(viewModel.loadError == nil)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "genre:Romance", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 40))
            let ids = entries.compactMap(\.manga?.id)
            #expect(ids == allPage.items.map(\.id) + page2.map(\.id))
            #expect(Set(ids).count == 40)
        }

        // MARK: - Title suggestions

        @Test func `updateSearchText with fewer than three characters requests nothing and leaves no suggestions key`() async throws {
            CatalogMockScenario.set(.mangasBeginsWith, .fixture("mangas_begins_dra.json"))

            viewModel.updateSearchText("dr")
            await viewModel.suggestionsTask?.value

            #expect(CatalogMockScenario.hits(.mangasBeginsWith) == 0)
            #expect(viewModel.suggestionsKey == nil)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.fetchAll(CatalogEntry.self, in: context).isEmpty)
        }

        @Test func `updateSearchText with three characters indexes eight suggestions after the debounce without touching the catalog mode`() async throws {
            CatalogMockScenario.set(.mangasBeginsWith, .fixture("mangas_begins_dra.json"))
            let fixtureIDs = try beginsWithIDs("mangas_begins_dra.json")
            #expect(fixtureIDs.count == 12)

            viewModel.updateSearchText("dra")
            await viewModel.suggestionsTask?.value

            #expect(CatalogMockScenario.hits(.mangasBeginsWith) == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.mangasBeginsWith))
            #expect(sent.path == "/search/mangasBeginsWith/dra")
            #expect(sent.queryValues.isEmpty)
            #expect(viewModel.suggestionsKey == "begins:dra")
            #expect(viewModel.currentMode == .all)
            #expect(viewModel.currentPage == 0)
            #expect(viewModel.loadError == nil)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "begins:dra", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 8))
            #expect(entries.compactMap(\.manga?.id) == Array(fixtureIDs.prefix(8)))
        }

        @Test func `Rapid typing collapses into one suggestions request for the last text`() async throws {
            CatalogMockScenario.set(.mangasBeginsWith, .fixture("mangas_begins_dra.json"))

            for text in ["d", "dr", "dra", "drag", "drago"] {
                viewModel.updateSearchText(text)
                try await Task.sleep(for: .milliseconds(50))
            }
            await viewModel.suggestionsTask?.value

            #expect(CatalogMockScenario.hits(.mangasBeginsWith) == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.mangasBeginsWith))
            #expect(sent.path?.hasSuffix("/drago") == true)
            #expect(viewModel.suggestionsKey == "begins:drago")
        }

        @Test func `A suggestions response arriving after the text changed never reaches the store`() async throws {
            CatalogMockScenario.set(.mangasBeginsWith, .delayed(for: .milliseconds(300), then: .fixture("mangas_begins_dra.json")))
            let ballItems = try PersistenceTestSupport.pageItems("mangas_contains_ball.json")

            viewModel.updateSearchText("dra")
            // Past the debounce: the "dra" request is on the wire and its response is still in flight.
            try await Task.sleep(for: .milliseconds(350))
            try CatalogMockScenario.set(.mangasBeginsWith, .data(encodedList(ballItems)))
            viewModel.updateSearchText("ball")
            // After "ball" settled, wait past the mock delay: a late "dra" response would have landed by now.
            await viewModel.suggestionsTask?.value
            try await Task.sleep(for: .milliseconds(400))

            let requests = CatalogMockScenario.requests(.mangasBeginsWith)
            #expect((1 ... 2).contains(requests.count))
            #expect(requests.last?.path == "/search/mangasBeginsWith/ball")
            #expect(viewModel.suggestionsKey == "begins:ball")

            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "begins:dra", in: context).isEmpty)
            let ball = try PersistenceTestSupport.catalogEntries(modeKey: "begins:ball", in: context)
            #expect(ball.map(\.ordinal) == Array(0 ..< 8))
            #expect(ball.compactMap(\.manga?.id) == Array(ballItems.prefix(8).map(\.id)))
        }

        @Test func `A failed suggestions request surfaces searchError and a later success clears it`() async throws {
            CatalogMockScenario.set(.mangasBeginsWith, .status(500))

            viewModel.updateSearchText("dra")
            await viewModel.suggestionsTask?.value

            let failure = try #require(viewModel.searchError)
            expectAPIError(.serverError, matches: failure)
            #expect(viewModel.suggestionsKey == nil)
            #expect(viewModel.loadError == nil)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "begins:dra", in: context).isEmpty)

            CatalogMockScenario.set(.mangasBeginsWith, .fixture("mangas_begins_dra.json"))
            viewModel.updateSearchText("drag")
            await viewModel.suggestionsTask?.value

            #expect(viewModel.searchError == nil)
            #expect(viewModel.suggestionsKey == "begins:drag")
        }

        @Test func `Typing below the minimum clears a pending searchError`() async {
            CatalogMockScenario.set(.mangasBeginsWith, .status(500))
            viewModel.updateSearchText("dra")
            await viewModel.suggestionsTask?.value
            #expect(viewModel.searchError != nil)

            viewModel.updateSearchText("dr")

            #expect(viewModel.searchError == nil)
            #expect(viewModel.suggestionsKey == nil)
        }

        // MARK: - Routing the field by its scope

        @Test func `search sends the text to the request of the scope in force`() async {
            CatalogMockScenario.set(.mangasBeginsWith, .fixture("mangas_begins_dra.json"))
            CatalogMockScenario.set(.searchAuthor, .fixture("authors_toriyama.json"))

            viewModel.search("dra")
            await viewModel.suggestionsTask?.value

            #expect(CatalogMockScenario.hits(.mangasBeginsWith) == 1)
            #expect(CatalogMockScenario.hits(.searchAuthor) == 0)
            #expect(viewModel.suggestionsKey == "begins:dra")

            viewModel.searchScope = .authors
            viewModel.search("toriya")
            await viewModel.authorTask?.value

            #expect(CatalogMockScenario.hits(.searchAuthor) == 1)
            #expect(CatalogMockScenario.hits(.mangasBeginsWith) == 1)
            #expect(viewModel.authorResults.first?.lastName == "Toriyama")
        }

        @Test func `submitSearch sends nothing while the Authors scope is in force`() async {
            CatalogMockScenario.set(.mangasContains, .fixture("mangas_contains_ball.json"))
            viewModel.searchScope = .authors
            viewModel.searchText = "ball"

            await viewModel.submitSearch()

            #expect(CatalogMockScenario.hits(.mangasContains) == 0)
            #expect(viewModel.currentMode == .all)
            #expect(!viewModel.currentMode.isFiltered)
        }

        @Test func `A new search clears the failure of the previous one before requesting`() async {
            CatalogMockScenario.set(.searchAuthor, .status(500))
            viewModel.searchAuthors("toriya")
            await viewModel.authorTask?.value
            #expect(viewModel.searchError != nil)

            CatalogMockScenario.set(.searchAuthor, .fixture("authors_toriyama.json"))
            viewModel.searchAuthors("toriyam")

            // Cleared when the request starts, not only when its answer arrives.
            #expect(viewModel.searchError == nil)
            await viewModel.authorTask?.value
            #expect(viewModel.searchError == nil)
            #expect(!viewModel.authorResults.isEmpty)
        }

        @Test func `hasAuthorQuery says whether the field asked for authors at all`() async {
            CatalogMockScenario.set(.searchAuthor, .fixture("authors_toriyama.json"))
            #expect(!viewModel.hasAuthorQuery)

            viewModel.searchAuthors("to")
            await viewModel.authorTask?.value
            #expect(viewModel.hasAuthorQuery)

            viewModel.searchAuthors("t")
            #expect(!viewModel.hasAuthorQuery)
        }

        // MARK: - Submit a title search

        @Test func `submitSearch loads the contains route paginated and clears the suggestions key`() async throws {
            CatalogMockScenario.set(.mangasBeginsWith, .fixture("mangas_begins_dra.json"))
            CatalogMockScenario.set(.mangasContains, .fixture("mangas_contains_ball.json"))
            let ballPage = try JSONDecoder.app.decode(MangaPageDTO.self, from: TestFixtures.data("mangas_contains_ball.json"))
            viewModel.updateSearchText("bal")
            await viewModel.suggestionsTask?.value
            #expect(viewModel.suggestionsKey != nil)

            viewModel.searchText = "ball"
            await viewModel.submitSearch()

            let sent = try #require(CatalogMockScenario.lastRequest(.mangasContains))
            #expect(sent.path == "/search/mangasContains/ball")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(CatalogMockScenario.hits(.mangasContains) == 1)
            #expect(viewModel.currentMode == .titleContains("ball"))
            #expect(viewModel.currentMode.title == "Results for \u{201C}ball\u{201D}")
            #expect(viewModel.currentMode.isFiltered)
            #expect(viewModel.totalCount == 79)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.suggestionsKey == nil)
            #expect(viewModel.loadError == nil)
            #expect(!viewModel.isLoading)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "contains:ball", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == ballPage.items.map(\.id))
        }

        // MARK: - Author lookup

        @Test func `searchAuthors requests the author route after the debounce and exposes the decoded authors`() async throws {
            CatalogMockScenario.set(.searchAuthor, .fixture("authors_toriyama.json"))

            viewModel.searchAuthors("toriya")
            await viewModel.authorTask?.value

            #expect(CatalogMockScenario.hits(.searchAuthor) == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.searchAuthor))
            #expect(sent.path == "/search/author/toriya")
            #expect(viewModel.authorResults.count == 6)
            #expect(viewModel.authorResults.first?.lastName == "Toriyama")
            #expect(viewModel.authorResults.first?.firstName == "Akira")
            #expect(viewModel.authorResults.first?.role == .storyAndArt)
        }

        @Test func `searchAuthors with a single character requests nothing and leaves no results`() async {
            CatalogMockScenario.set(.searchAuthor, .fixture("authors_toriyama.json"))

            viewModel.searchAuthors("t")
            await viewModel.authorTask?.value

            #expect(CatalogMockScenario.hits(.searchAuthor) == 0)
            #expect(viewModel.authorResults.isEmpty)
        }

        @Test func `searchAuthors is in flight from the key stroke until the results land`() async {
            CatalogMockScenario.set(.searchAuthor, .fixture("authors_toriyama.json"))
            #expect(!viewModel.isSearchingAuthors)

            viewModel.searchAuthors("toriya")
            #expect(viewModel.isSearchingAuthors)

            await viewModel.authorTask?.value
            #expect(!viewModel.isSearchingAuthors)
            #expect(viewModel.authorResults.count == 6)
        }

        @Test func `searchAuthors is no longer in flight after a failure or below the minimum`() async {
            CatalogMockScenario.set(.searchAuthor, .status(500))

            viewModel.searchAuthors("toriya")
            await viewModel.authorTask?.value
            #expect(!viewModel.isSearchingAuthors)
            #expect(viewModel.searchError != nil)

            viewModel.searchAuthors("toriya")
            #expect(viewModel.isSearchingAuthors)
            viewModel.searchAuthors("t")
            #expect(!viewModel.isSearchingAuthors)
        }

        @Test func `Rapid author typing collapses into one request for the last query`() async throws {
            CatalogMockScenario.set(.searchAuthor, .fixture("authors_toriyama.json"))

            for query in ["to", "tori", "toriya"] {
                viewModel.searchAuthors(query)
                try await Task.sleep(for: .milliseconds(50))
            }
            await viewModel.authorTask?.value

            #expect(CatalogMockScenario.hits(.searchAuthor) == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.searchAuthor))
            #expect(sent.path == "/search/author/toriya")
            #expect(viewModel.authorResults.count == 6)
        }

        @Test func `select author loads the author filter by id with the full name as title`() async throws {
            CatalogMockScenario.set(.mangaByAuthor, .fixture("mangas_page.json"))
            let authors = try JSONDecoder.app.decode([AuthorDTO].self, from: TestFixtures.data("authors_toriyama.json"))
            let toriyama = try #require(authors.first)

            await viewModel.select(author: toriyama)

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByAuthor))
            let path = try #require(sent.path)
            #expect(path.lowercased() == "/list/mangaByAuthor/\(toriyama.id.uuidString)".lowercased())
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(viewModel.currentMode == .byAuthor(id: toriyama.id, name: "Akira Toriyama"))
            #expect(viewModel.currentMode.title == "Akira Toriyama")
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.loadError == nil)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: viewModel.currentMode.modeKey, in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
        }

        @Test func `select author with an empty first name titles the filter with the last name only`() async throws {
            CatalogMockScenario.set(.mangaByAuthor, .fixture("mangas_page.json"))
            let authors = try JSONDecoder.app.decode([AuthorDTO].self, from: TestFixtures.data("authors_toriyama.json"))
            // Second author of the fixture: "Toriyasu" with an empty first name.
            let toriyasu = try #require(authors.first { $0.firstName.isEmpty })
            #expect(toriyasu.lastName == "Toriyasu")

            await viewModel.select(author: toriyasu)

            #expect(viewModel.currentMode.title == "Toriyasu")
            #expect(CatalogMockScenario.hits(.mangaByAuthor) == 1)
        }

        @Test func `A failed author search surfaces searchError and keeps the results empty`() async throws {
            CatalogMockScenario.set(.searchAuthor, .status(500))

            viewModel.searchAuthors("toriya")
            await viewModel.authorTask?.value

            let failure = try #require(viewModel.searchError)
            expectAPIError(.serverError, matches: failure)
            #expect(viewModel.authorResults.isEmpty)
            #expect(viewModel.loadError == nil)

            CatalogMockScenario.set(.searchAuthor, .fixture("authors_toriyama.json"))
            viewModel.searchAuthors("toriyama")
            await viewModel.authorTask?.value

            #expect(viewModel.searchError == nil)
            #expect(viewModel.authorResults.count == 6)
        }

        // MARK: - Advanced search

        @Test func `applyAdvancedSearch posts the normalized draft paginated and indexes the results under the search key`() async throws {
            CatalogMockScenario.set(.customSearch, .fixture("search_custom.json"))
            let resultPage = try JSONDecoder.app.decode(MangaPageDTO.self, from: TestFixtures.data("search_custom.json"))
            viewModel.draftTitle = "dragon"
            for genre in ["Adventure", "Action"] {
                viewModel.draftGenres.insert(genre)
            }
            viewModel.draftContains = true
            // The author fields and the other two sets are left as the form opens them.
            let draft = viewModel.searchDraft

            await viewModel.applyAdvancedSearch()

            #expect(CatalogMockScenario.hits(.customSearch) == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.customSearch))
            #expect(sent.method == "POST")
            #expect(sent.path == "/search/manga")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            let body = try sent.decodedBody(as: CustomSearch.self)
            #expect(body == draft.normalized)
            #expect(body.searchTitle == "dragon")
            #expect(body.searchGenres == ["Action", "Adventure"])
            #expect(body.searchContains)
            let bodyData = try #require(sent.body)
            let rawBody = String(decoding: bodyData, as: UTF8.self)
            #expect(!rawBody.contains("searchAuthorFirstName"))
            #expect(!rawBody.contains("searchAuthorLastName"))
            #expect(!rawBody.contains("searchThemes"))
            #expect(!rawBody.contains("searchDemographics"))

            #expect(viewModel.currentMode.title == "Advanced search")
            #expect(viewModel.currentMode.isFiltered)
            #expect(viewModel.totalCount == 111)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.loadError == nil)
            #expect(!viewModel.isLoading)
            // The draft survives the search so the form reopens with the same values.
            #expect(viewModel.searchDraft == draft)

            let context = PersistenceTestSupport.freshContext(container)
            let modeKey = CatalogMode.search(viewModel.searchDraft.normalized).modeKey
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: modeKey, in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == resultPage.items.map(\.id))
        }

        @Test(arguments: [true, false])
        func `normalized turns blank strings and empty arrays into nil and keeps the rest`(contains: Bool) {
            let draft = CustomSearch(
                searchTitle: "",
                searchAuthorFirstName: "   ",
                searchAuthorLastName: "Toriyama",
                searchGenres: [],
                searchThemes: ["Martial Arts"],
                searchDemographics: nil,
                searchContains: contains
            )

            let normalized = draft.normalized

            #expect(normalized.searchTitle == nil)
            #expect(normalized.searchAuthorFirstName == nil)
            #expect(normalized.searchAuthorLastName == "Toriyama")
            #expect(normalized.searchGenres == nil)
            #expect(normalized.searchThemes == ["Martial Arts"])
            #expect(normalized.searchDemographics == nil)
            #expect(normalized.searchContains == contains)
        }

        @Test func `normalized leaves an already normal draft and the empty draft unchanged`() {
            let normal = CustomSearch(
                searchTitle: "dragon",
                searchAuthorFirstName: nil,
                searchAuthorLastName: nil,
                searchGenres: ["Action"],
                searchThemes: nil,
                searchDemographics: ["Shounen"],
                searchContains: false
            )

            #expect(normal.normalized == normal)
            #expect(CustomSearch.empty.normalized == .empty)
        }

        // MARK: - The advanced search form

        /// Every list is read back in the order the server sent it, never in the order the chips
        /// were tapped. The themes and the demographics picked here come back in an order that is
        /// not the alphabetical one either, so no accidental ordering can satisfy the test.
        @Test func `The draft lists the picked categories in the order the server sent them`() async {
            CatalogMockScenario.set([
                .listGenres: .fixture("genres.json"),
                .listThemes: .fixture("themes.json"),
                .listDemographics: .fixture("demographics.json"),
            ])
            await viewModel.loadTaxonomies()

            for genre in ["Adventure", "Action"] {
                viewModel.draftGenres.insert(genre)
            }
            for theme in ["Historical", "Psychological", "Gore", "Samurai"] {
                viewModel.draftThemes.insert(theme)
            }
            for demographic in ["Kids", "Josei", "Shounen"] {
                viewModel.draftDemographics.insert(demographic)
            }

            let draft = viewModel.searchDraft

            #expect(draft.searchGenres == ["Action", "Adventure"])
            #expect(draft.searchThemes == ["Gore", "Psychological", "Historical", "Samurai"])
            #expect(draft.searchDemographics == ["Shounen", "Josei", "Kids"])
        }

        /// The key indexes the stored results, so the same criteria must always produce the same
        /// one: twice in a row, and whichever order the chips were tapped in.
        @Test func `The search key of a draft does not depend on the order the categories were picked`() async {
            CatalogMockScenario.set([
                .listGenres: .fixture("genres.json"),
                .listThemes: .fixture("themes.json"),
                .listDemographics: .fixture("demographics.json"),
            ])
            await viewModel.loadTaxonomies()
            viewModel.draftTitle = "dragon"
            viewModel.draftContains = true
            for genre in ["Supernatural", "Action", "Romance", "Mystery", "Comedy"] {
                viewModel.draftGenres.insert(genre)
            }

            let key = CatalogMode.search(viewModel.searchDraft.normalized).modeKey

            #expect(CatalogMode.search(viewModel.searchDraft.normalized).modeKey == key)

            viewModel.draftGenres = []
            for genre in ["Comedy", "Mystery", "Romance", "Action", "Supernatural"] {
                viewModel.draftGenres.insert(genre)
            }

            #expect(CatalogMode.search(viewModel.searchDraft.normalized).modeKey == key)
            // Same criteria spelled in the order of the server list: the key of those results.
            let serverOrdered = CustomSearch(
                searchTitle: "dragon",
                searchAuthorFirstName: nil,
                searchAuthorLastName: nil,
                searchGenres: ["Action", "Supernatural", "Mystery", "Comedy", "Romance"],
                searchThemes: nil,
                searchDemographics: nil,
                searchContains: true
            )
            #expect(CatalogMode.search(serverOrdered).modeKey == key)
        }

        /// The form is usable before the lists arrive (or when they failed): the picks are then
        /// sorted alphabetically, which for these values is not the order they were picked in.
        @Test func `Without the server lists the draft falls back to alphabetical order`() {
            #expect(viewModel.taxonomies == nil)

            for genre in ["Supernatural", "Mystery", "Action"] {
                viewModel.draftGenres.insert(genre)
            }
            for theme in ["Psychological", "Historical", "Gore", "Samurai"] {
                viewModel.draftThemes.insert(theme)
            }
            for demographic in ["Shounen", "Josei"] {
                viewModel.draftDemographics.insert(demographic)
            }

            let draft = viewModel.searchDraft

            #expect(draft.searchGenres == ["Action", "Mystery", "Supernatural"])
            #expect(draft.searchThemes == ["Gore", "Historical", "Psychological", "Samurai"])
            #expect(draft.searchDemographics == ["Josei", "Shounen"])
        }

        @Test(arguments: [true, false])
        func `A blank field or an untouched list is left out of the search, and the contains toggle travels as it is`(
            contains: Bool
        ) {
            viewModel.draftTitle = "  "
            viewModel.draftAuthorLastName = "Toriyama"
            viewModel.draftContains = contains

            let search = viewModel.searchDraft.normalized

            #expect(search.searchTitle == nil)
            #expect(search.searchAuthorFirstName == nil)
            #expect(search.searchAuthorLastName == "Toriyama")
            #expect(search.searchGenres == nil)
            #expect(search.searchThemes == nil)
            #expect(search.searchDemographics == nil)
            #expect(search.searchContains == contains)
        }

        @Test func `resetDraft returns the draft to empty after it was filled`() {
            viewModel.draftTitle = "dragon"
            viewModel.draftAuthorFirstName = "Akira"
            viewModel.draftAuthorLastName = "Toriyama"
            viewModel.draftGenres = ["Action"]
            viewModel.draftThemes = ["Martial Arts"]
            viewModel.draftDemographics = ["Shounen"]
            viewModel.draftContains = true
            #expect(viewModel.searchDraft.normalized != .empty)

            viewModel.resetDraft()

            // A search from here would carry no criteria at all.
            #expect(viewModel.searchDraft.normalized == .empty)
        }

        // MARK: - Clear filter

        @Test func `Switching mode drops the previous total until the new page lands`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            CatalogMockScenario.set(.mangaByGenre, .delayed(for: .milliseconds(300), then: .fixture("mangas_page.json")))
            await viewModel.loadInitial(mode: .all)
            #expect(viewModel.totalCount == allPage.metadata.total)

            let viewModel = viewModel
            let filtered = Task { await viewModel.loadInitial(mode: .byGenre("Romance")) }
            try await Task.sleep(for: .milliseconds(50))

            #expect(viewModel.isLoading)
            #expect(viewModel.totalCount == nil)
            #expect(viewModel.totalPages == nil)
            await filtered.value
            #expect(viewModel.totalCount == allPage.metadata.total)
        }

        @Test func `Refreshing the same mode keeps its total while the page reloads`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            CatalogMockScenario.set(.listMangas, .delayed(for: .milliseconds(300), then: .fixture("mangas_page.json")))

            let viewModel = viewModel
            let refreshed = Task { await viewModel.refresh() }
            try await Task.sleep(for: .milliseconds(50))

            #expect(viewModel.isLoading)
            #expect(viewModel.totalCount == allPage.metadata.total)
            await refreshed.value
            #expect(viewModel.totalCount == allPage.metadata.total)
        }
    }
}

// MARK: - Fixture builders

private extension SharedMockSuites.CatalogViewModelSearchTests {
    /// The paginated envelope the backend would send for `items` as page `number` of a filter
    /// route, with the server total of the page-1 fixture, encoded with the app encoder so the
    /// real decoder reads it back.
    func encodedPage(_ items: [MangaDTO], page number: Int) throws -> Data {
        let dto = MangaPageDTO(metadata: PageMetadataDTO(total: allPage.metadata.total, page: number, per: 20), items: items)
        return try JSONEncoder.app.encode(dto)
    }

    /// The unpaginated `[MangaDTO]` body of `/search/mangasBeginsWith/{q}`.
    func encodedList(_ items: [MangaDTO]) throws -> Data {
        try JSONEncoder.app.encode(items)
    }

    /// Ids of an unpaginated `[MangaDTO]` fixture, in server order.
    func beginsWithIDs(_ fixture: String) throws -> [Int] {
        try JSONDecoder.app.decode([MangaDTO].self, from: TestFixtures.data(fixture)).map(\.id)
    }
}
