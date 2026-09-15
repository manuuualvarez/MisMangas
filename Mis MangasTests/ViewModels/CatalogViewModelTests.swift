//
//  CatalogViewModelTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

extension SharedMockSuites {
    /// The catalog's control state driven through the real pipeline: ViewModel → service →
    /// mocked transport → decode → `MangaSyncActor` → store. The ViewModel never exposes rows,
    /// so the oracle for "what the screen shows" is a fresh `ModelContext` over the same
    /// container, exactly as the catalog query reads it. The other oracles are the requests the
    /// mock captured (hits, page and per) and the ids and `metadata.total` of the fixtures.
    @Suite("CatalogViewModel")
    @MainActor
    struct CatalogViewModelTests {
        /// `metadata.total` of every page fixture captured from the backend.
        private static let serverTotal = 64833
        /// Pages of 20 needed for 64,833 mangas: 3,241 full pages plus one partial.
        private static let serverPages = 3242

        private let viewModel: CatalogViewModel
        private let container: ModelContainer
        /// First 20 items of `/list/mangas`, in server order.
        private let allPage1: [MangaDTO]

        init() throws {
            CatalogMockScenario.reset()
            let made = try PersistenceTestSupport.makeActor()
            container = made.container
            let service = MangaSyncService(syncActor: made.actor, mangaRepository: DefaultMangaRepositoryTest())
            viewModel = CatalogViewModel(syncService: service)
            allPage1 = try PersistenceTestSupport.pageItems("mangas_page.json")
        }

        // MARK: - First page

        @Test func `loadInitial all indexes the first page and reports the server totals`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))

            await viewModel.loadInitial(mode: .all)

            let sent = try #require(CatalogMockScenario.lastRequest(.listMangas))
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(CatalogMockScenario.hits(.listMangas) == 1)
            #expect(CatalogMockScenario.hits(.listBestMangas) == 0)

            #expect(viewModel.currentMode == .all)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.hasNextPage)
            #expect(viewModel.totalCount == Self.serverTotal)
            #expect(viewModel.totalPages == Self.serverPages)
            #expect(!viewModel.isLoading)
            #expect(viewModel.loadError == nil)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == allPage1.map(\.id))
        }

        @Test func `A short page leaves the index empty and reports no next page`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page_empty.json"))

            await viewModel.loadInitial(mode: .all)

            #expect(!viewModel.hasNextPage)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.totalCount == Self.serverTotal)
            #expect(viewModel.loadError == nil)
            #expect(!viewModel.isLoading)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).isEmpty)
        }

        @Test func `No network on the first load surfaces transport and leaves the store empty`() async throws {
            CatalogMockScenario.set(.listMangas, .transportError(.notConnectedToInternet))

            await viewModel.loadInitial(mode: .all)

            let error = try #require(viewModel.loadError)
            expectAPIError(.transport, matches: error)
            #expect(!viewModel.isLoading)
            #expect(viewModel.currentMode == .all)
            #expect(CatalogMockScenario.hits(.listMangas) == 1)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.fetchAll(CatalogEntry.self, in: context).isEmpty)
            #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
        }

        // MARK: - Next page

        @Test func `loadMore requests page 2 with the same per and appends 20 unseen mangas`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            let page2 = page(2)
            try CatalogMockScenario.set(.listMangas, .data(encodedPage(page2, page: 2)))

            await viewModel.loadMore()

            let requests = CatalogMockScenario.requests(.listMangas)
            #expect(requests.count == 2)
            #expect(requests.last?.queryValues == ["page": "2", "per": "20"])
            #expect(viewModel.currentPage == 2)
            #expect(viewModel.hasNextPage)
            #expect(viewModel.loadError == nil)
            #expect(!viewModel.isLoading)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 40))
            let ids = entries.compactMap(\.manga?.id)
            #expect(ids == allPage1.map(\.id) + page2.map(\.id))
            #expect(Set(ids).count == 40)
        }

        @Test func `loadMore does nothing when there is no next page`() async {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page_empty.json"))
            await viewModel.loadInitial(mode: .all)
            #expect(!viewModel.hasNextPage)

            await viewModel.loadMore()

            #expect(CatalogMockScenario.hits(.listMangas) == 1)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.loadError == nil)
        }

        @Test func `loadMore does nothing while a load is in flight`() async throws {
            CatalogMockScenario.set(.listMangas, .delayed(for: .milliseconds(300), then: .fixture("mangas_page.json")))
            let viewModel = viewModel
            let initial = Task { await viewModel.loadInitial(mode: .all) }
            try await Task.sleep(for: .milliseconds(50))
            #expect(viewModel.isLoading)

            await viewModel.loadMore()

            #expect(CatalogMockScenario.hits(.listMangas) == 1)
            await initial.value
            #expect(CatalogMockScenario.hits(.listMangas) == 1)
            #expect(!viewModel.isLoading)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.hasNextPage)
            let context = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).count == 20)
        }

        @Test func `A loadMore queued right behind loadInitial does not start a second request`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            let viewModel = viewModel

            // No suspension between the two: the main actor runs the jobs in order, so `loadMore`
            // observes whatever `loadInitial` set before its first `await`.
            let initial = Task { await viewModel.loadInitial(mode: .all) }
            let more = Task { await viewModel.loadMore() }
            await initial.value
            await more.value

            #expect(CatalogMockScenario.hits(.listMangas) == 1)
            let sent = try #require(CatalogMockScenario.lastRequest(.listMangas))
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.hasNextPage)
            #expect(!viewModel.isLoading)
            #expect(viewModel.loadError == nil)
            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
        }

        @Test func `Five consecutive pages produce five requests with per 20 and 100 distinct mangas`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            for number in 2 ... 5 {
                try CatalogMockScenario.set(.listMangas, .data(encodedPage(page(number), page: number)))
                await viewModel.loadMore()
            }

            let requests = CatalogMockScenario.requests(.listMangas)
            #expect(requests.count == 5)
            #expect(requests.compactMap { $0.queryValues["per"] } == Array(repeating: "20", count: 5))
            #expect(requests.compactMap { $0.queryValues["page"] } == ["1", "2", "3", "4", "5"])
            #expect(viewModel.currentPage == 5)
            #expect(viewModel.loadError == nil)

            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 100))
            let ids = entries.compactMap(\.manga?.id)
            #expect(ids.count == 100)
            #expect(Set(ids).count == 100)
        }

        // MARK: - Failures after the first page

        @Test func `A 500 on page 3 surfaces serverError and keeps the 40 entries already indexed`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            try CatalogMockScenario.set(.listMangas, .data(encodedPage(page(2), page: 2)))
            await viewModel.loadMore()
            CatalogMockScenario.set(.listMangas, .status(500))

            await viewModel.loadMore()

            let error = try #require(viewModel.loadError)
            expectAPIError(.serverError, matches: error)
            #expect(CatalogMockScenario.hits(.listMangas) == 3)
            #expect(viewModel.currentPage == 2)
            #expect(!viewModel.isLoading)
            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 40))
        }

        @Test func `Retrying after a failed page 3 requests page 3 again and clears the error`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            try CatalogMockScenario.set(.listMangas, .data(encodedPage(page(2), page: 2)))
            await viewModel.loadMore()
            CatalogMockScenario.set(.listMangas, .status(500))
            await viewModel.loadMore()
            #expect(viewModel.loadError != nil)
            try CatalogMockScenario.set(.listMangas, .data(encodedPage(page(3), page: 3)))

            await viewModel.loadMore()

            let requests = CatalogMockScenario.requests(.listMangas)
            #expect(requests.count == 4)
            #expect(requests.last?.queryValues == ["page": "3", "per": "20"])
            #expect(viewModel.loadError == nil)
            #expect(viewModel.currentPage == 3)
            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 60))
        }

        @Test func `Retry after a failed page 3 requests page 3 again`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            try CatalogMockScenario.set(.listMangas, .data(encodedPage(page(2), page: 2)))
            await viewModel.loadMore()
            CatalogMockScenario.set(.listMangas, .status(500))
            await viewModel.loadMore()
            #expect(viewModel.loadError != nil)
            try CatalogMockScenario.set(.listMangas, .data(encodedPage(page(3), page: 3)))

            await viewModel.retry()

            let requests = CatalogMockScenario.requests(.listMangas)
            #expect(requests.count == 4)
            #expect(requests.last?.queryValues == ["page": "3", "per": "20"])
            #expect(viewModel.loadError == nil)
            #expect(viewModel.currentPage == 3)
            #expect(!viewModel.isLoading)
            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 60))
        }

        @Test func `Retry after a failed refresh requests page 1 again and keeps the mode`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            try CatalogMockScenario.set(.listMangas, .data(encodedPage(page(2), page: 2)))
            await viewModel.loadMore()
            CatalogMockScenario.set(.listMangas, .transportError(.notConnectedToInternet))
            await viewModel.refresh()
            let failure = try #require(viewModel.loadError)
            expectAPIError(.transport, matches: failure)
            let before = PersistenceTestSupport.freshContext(container)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: before).count == 40)
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))

            await viewModel.retry()

            let requests = CatalogMockScenario.requests(.listMangas)
            #expect(requests.count == 4)
            #expect(requests.last?.queryValues == ["page": "1", "per": "20"])
            #expect(viewModel.currentMode == .all)
            #expect(viewModel.loadError == nil)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.hasNextPage)
            #expect(!viewModel.isLoading)
            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == allPage1.map(\.id))
        }

        @Test func `A failed refresh keeps the last catalog visible`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            CatalogMockScenario.set(.listMangas, .transportError(.notConnectedToInternet))

            await viewModel.refresh()

            let error = try #require(viewModel.loadError)
            expectAPIError(.transport, matches: error)
            #expect(!viewModel.isLoading)
            #expect(viewModel.currentPage == 1)
            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == allPage1.map(\.id))
        }

        // MARK: - Refresh

        @Test func `refresh reloads page 1 of the current mode and discards the pages after it`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))
            await viewModel.loadInitial(mode: .all)
            try CatalogMockScenario.set(.listMangas, .data(encodedPage(page(2), page: 2)))
            await viewModel.loadMore()
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))

            await viewModel.refresh()

            let requests = CatalogMockScenario.requests(.listMangas)
            #expect(requests.count == 3)
            #expect(requests.last?.queryValues == ["page": "1", "per": "20"])
            #expect(viewModel.currentMode == .all)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.hasNextPage)
            #expect(viewModel.loadError == nil)
            let context = PersistenceTestSupport.freshContext(container)
            let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context)
            #expect(entries.map(\.ordinal) == Array(0 ..< 20))
            #expect(entries.compactMap(\.manga?.id) == allPage1.map(\.id))
        }

        // MARK: - Mode change

        @Test func `Switching mode cancels the load in flight and the late response never reaches the store`() async throws {
            CatalogMockScenario.set(.listMangas, .delayed(for: .milliseconds(300), then: .fixture("mangas_page.json")))
            CatalogMockScenario.set(.listBestMangas, .fixture("mangas_page_best.json"))
            let bestIDs = try PersistenceTestSupport.pageItems("mangas_page_best.json").map(\.id)
            let viewModel = viewModel
            let stale = Task { await viewModel.loadInitial(mode: .all) }
            try await Task.sleep(for: .milliseconds(50))

            await viewModel.loadInitial(mode: .best)

            await stale.value
            // Longer than the mock delay: a late "all" response would have landed by now.
            try await Task.sleep(for: .milliseconds(400))
            #expect(CatalogMockScenario.hits(.listMangas) == 1)
            #expect(CatalogMockScenario.hits(.listBestMangas) == 1)
            #expect(viewModel.currentMode == .best)
            #expect(viewModel.currentPage == 1)
            #expect(viewModel.hasNextPage)
            #expect(viewModel.loadError == nil)
            #expect(!viewModel.isLoading)

            let context = PersistenceTestSupport.freshContext(container)
            let best = try PersistenceTestSupport.catalogEntries(modeKey: "best", in: context)
            #expect(best.map(\.ordinal) == Array(0 ..< 20))
            #expect(best.compactMap(\.manga?.id) == bestIDs)
            #expect(try PersistenceTestSupport.catalogEntries(modeKey: "all", in: context).isEmpty)
        }
    }
}

// MARK: - Page builders

private extension SharedMockSuites.CatalogViewModelTests {
    /// Page `number` of the "all" mode: page 1 is the real fixture; the following pages reuse its
    /// 20 items with ids shifted out of every other page's range, so ids stay distinct across pages.
    func page(_ number: Int) -> [MangaDTO] {
        number == 1 ? allPage1 : allPage1.shiftingIDs(by: (number - 1) * 100_000)
    }

    /// The paginated envelope the backend would send for `items` as page `number`, encoded with
    /// the app encoder so the real decoder reads it back.
    func encodedPage(_ items: [MangaDTO], page number: Int) throws -> Data {
        let dto = MangaPageDTO(metadata: PageMetadataDTO(total: Self.serverTotal, page: number, per: 20), items: items)
        return try JSONEncoder.app.encode(dto)
    }
}
