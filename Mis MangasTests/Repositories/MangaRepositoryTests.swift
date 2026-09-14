//
//  MangaRepositoryTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

extension SharedMockSuites {
    /// Every method of `MangaRepository` through the real pipeline (endpoint → request → transport
    /// → decode). Oracles: the request `URLSession` actually handed to `URLSessionMockInterface`
    /// (method, path, query, headers, body) checked against the backend OpenAPI, and the
    /// content of the served fixture.
    @Suite("MangaRepository")
    struct MangaRepositoryTests {
        private let repository: any MangaRepository = DefaultMangaRepositoryTest()

        init() {
            CatalogMockScenario.reset()
        }

        // MARK: - Catalog listings

        @Test func `fetchMangas emits GET list mangas with page and per and decodes the page`() async throws {
            CatalogMockScenario.set(.listMangas, .fixture("mangas_page.json"))

            let page = try await repository.fetchMangas(page: 2, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.listMangas))
            #expect(sent.method == "GET")
            #expect(sent.path == "/list/mangas")
            #expect(sent.queryValues == ["page": "2", "per": "20"])
            #expect(sent.header("Accept") == "application/json")
            #expect(CatalogMockScenario.hits(.listMangas) == 1)

            #expect(page.items.count == 20)
            #expect(page.metadata.total == 64833)
            #expect(page.items.first?.title == "Monster")
        }

        @Test func `fetchBestMangas emits GET list bestMangas and keeps the server order`() async throws {
            CatalogMockScenario.set(.listBestMangas, .fixture("mangas_page_best.json"))

            let page = try await repository.fetchBestMangas(page: 1, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.listBestMangas))
            #expect(sent.method == "GET")
            #expect(sent.path == "/list/bestMangas")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
            #expect(CatalogMockScenario.hits(.listMangas) == 0)

            #expect(page.items.first?.id == 2)
            #expect(page.items.first?.score == 9.47)
        }

        @Test(arguments: [
            ("Drama", "/list/mangaByGenre/Drama"),
            ("Slice of Life", "/list/mangaByGenre/Slice of Life"),
        ])
        func `fetchMangasByGenre puts the genre in the path, spaces included`(genre: String, path: String) async throws {
            CatalogMockScenario.set(.mangaByGenre, .fixture("mangas_page.json"))

            let page = try await repository.fetchMangasByGenre(genre, page: 3, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByGenre))
            #expect(sent.method == "GET")
            #expect(sent.path == path)
            #expect(sent.queryValues == ["page": "3", "per": "20"])
            #expect(page.items.count == 20)
        }

        @Test func `fetchMangasByTheme emits GET list mangaByTheme`() async throws {
            CatalogMockScenario.set(.mangaByTheme, .fixture("mangas_page.json"))

            _ = try await repository.fetchMangasByTheme("Psychological", page: 1, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByTheme))
            #expect(sent.path == "/list/mangaByTheme/Psychological")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
        }

        @Test func `fetchMangasByDemographic emits GET list mangaByDemographic`() async throws {
            CatalogMockScenario.set(.mangaByDemographic, .fixture("mangas_page.json"))

            _ = try await repository.fetchMangasByDemographic("Seinen", page: 1, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByDemographic))
            #expect(sent.path == "/list/mangaByDemographic/Seinen")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
        }

        @Test func `fetchMangasByAuthor puts the author UUID in the path`() async throws {
            CatalogMockScenario.set(.mangaByAuthor, .fixture("mangas_page.json"))
            let authorID = try #require(UUID(uuidString: "54BE174C-2FE9-42C8-A842-85D291A6AEDD"))

            _ = try await repository.fetchMangasByAuthor(authorID, page: 1, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByAuthor))
            #expect(sent.path == "/list/mangaByAuthor/54BE174C-2FE9-42C8-A842-85D291A6AEDD")
            #expect(sent.queryValues == ["page": "1", "per": "20"])
        }

        // MARK: - Detail

        @Test func `fetchManga emits GET search manga id and decodes the manga`() async throws {
            CatalogMockScenario.set(.mangaByID, .fixture("manga_monster.json"))

            let manga = try await repository.fetchManga(id: 42)

            let sent = try #require(CatalogMockScenario.lastRequest(.mangaByID))
            #expect(sent.method == "GET")
            #expect(sent.path == "/search/manga/42")
            #expect(sent.queryValues.isEmpty)
            #expect(manga.title == "Monster")
            #expect(manga.genres.map(\.genre) == ["Award Winning", "Drama", "Mystery"])
        }

        // MARK: - Taxonomies (the API returns plain string arrays)

        @Test func `fetchAllGenres decodes the 21 live genres as strings`() async throws {
            CatalogMockScenario.set(.listGenres, .fixture("genres.json"))

            let genres = try await repository.fetchAllGenres()

            let sent = try #require(CatalogMockScenario.lastRequest(.listGenres))
            #expect(sent.method == "GET")
            #expect(sent.path == "/list/genres")
            #expect(sent.queryValues.isEmpty)
            #expect(genres.count == 21)
            #expect(genres.first == "Action")
            #expect(genres.contains("Slice of Life"))
        }

        @Test func `fetchAllThemes decodes the 52 live themes as strings`() async throws {
            CatalogMockScenario.set(.listThemes, .fixture("themes.json"))

            let themes = try await repository.fetchAllThemes()

            let sent = try #require(CatalogMockScenario.lastRequest(.listThemes))
            #expect(sent.path == "/list/themes")
            #expect(themes.count == 52)
            #expect(themes.contains("Idols (Female)"))
        }

        @Test func `fetchAllDemographics decodes the 5 live demographics as strings`() async throws {
            CatalogMockScenario.set(.listDemographics, .fixture("demographics.json"))

            let demographics = try await repository.fetchAllDemographics()

            let sent = try #require(CatalogMockScenario.lastRequest(.listDemographics))
            #expect(sent.path == "/list/demographics")
            #expect(demographics.count == 5)
            #expect(demographics.contains("Seinen"))
        }

        // MARK: - Authors

        @Test func `fetchAuthorsPage emits GET list authorsPaged and decodes an author page`() async throws {
            CatalogMockScenario.set(.listAuthorsPaged, .json(Self.authorsPageJSON))

            let page = try await repository.fetchAuthorsPage(page: 4, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.listAuthorsPaged))
            #expect(sent.method == "GET")
            #expect(sent.path == "/list/authorsPaged")
            #expect(sent.queryValues == ["page": "4", "per": "20"])
            #expect(page.metadata.total == 2)
            #expect(page.items.map(\.lastName) == ["Miura", "Studio Gaga"])
        }

        @Test func `fetchAuthors posts the UUIDs it was given as an ids array`() async throws {
            CatalogMockScenario.set(.authorsByIds, .json(Self.authorsJSON))
            let ids = [UUID(), UUID()]

            let authors = try await repository.fetchAuthors(ids: ids)

            let sent = try #require(CatalogMockScenario.lastRequest(.authorsByIds))
            #expect(sent.method == "POST")
            #expect(sent.path == "/list/authorsByIds")
            #expect(sent.header("Content-Type")?.hasPrefix("application/json") == true)
            // Contract shape `{ "ids": [String] }`, decoded independently of the production body type.
            let body = try sent.decodedBody(as: [String: [String]].self)
            #expect(body == ["ids": ids.map(\.uuidString)])
            #expect(authors.map(\.firstName) == ["Kentarou", "Akira"])
        }

        @Test func `searchAuthors emits GET search author query and decodes the flat array`() async throws {
            CatalogMockScenario.set(.searchAuthor, .json(Self.authorsJSON))

            let authors = try await repository.searchAuthors("toriyama")

            let sent = try #require(CatalogMockScenario.lastRequest(.searchAuthor))
            #expect(sent.method == "GET")
            #expect(sent.path == "/search/author/toriyama")
            #expect(sent.queryValues.isEmpty)
            #expect(authors.map(\.lastName) == ["Miura", "Toriyama"])
            #expect(authors.last?.role == .storyAndArt)
        }

        // MARK: - Search

        @Test func `searchBeginsWith emits GET search mangasBeginsWith and decodes an unpaged array`() async throws {
            CatalogMockScenario.set(.mangasBeginsWith, .json(Self.dragonMangasJSON))

            let mangas = try await repository.searchBeginsWith("dragon")

            let sent = try #require(CatalogMockScenario.lastRequest(.mangasBeginsWith))
            #expect(sent.method == "GET")
            #expect(sent.path == "/search/mangasBeginsWith/dragon")
            #expect(sent.queryValues.isEmpty)
            #expect(mangas.map(\.id) == [42, 43])
            #expect(mangas.map(\.title) == ["Dragon Ball", "Dragon Quest: Dai no Daibouken"])
        }

        @Test func `searchContains emits GET search mangasContains with page and per`() async throws {
            CatalogMockScenario.set(.mangasContains, .fixture("mangas_page.json"))

            let page = try await repository.searchContains("ball", page: 3, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.mangasContains))
            #expect(sent.method == "GET")
            #expect(sent.path == "/search/mangasContains/ball")
            #expect(sent.queryValues == ["page": "3", "per": "20"])
            #expect(page.items.count == 20)
        }

        @Test func `customSearch posts the CustomSearch body to search manga with page and per`() async throws {
            CatalogMockScenario.set(.customSearch, .fixture("mangas_page.json"))
            let search = CustomSearch(
                searchTitle: "Monster",
                searchAuthorFirstName: nil,
                searchAuthorLastName: "Urasawa",
                searchGenres: ["Drama", "Mystery"],
                searchThemes: nil,
                searchDemographics: ["Seinen"],
                searchContains: true
            )

            let page = try await repository.customSearch(search, page: 2, per: 20)

            let sent = try #require(CatalogMockScenario.lastRequest(.customSearch))
            #expect(sent.method == "POST")
            #expect(sent.path == "/search/manga")
            #expect(sent.queryValues == ["page": "2", "per": "20"])
            #expect(sent.header("Content-Type")?.hasPrefix("application/json") == true)
            #expect(try sent.decodedBody(as: CustomSearch.self) == search)
            #expect(CatalogMockScenario.hits(.mangaByID) == 0)
            #expect(page.items.count == 20)
        }

        // MARK: - Inline fixtures (shapes from the backend OpenAPI)

        private static let authorsJSON = """
        [
          { "id": "6F0B6948-08C4-4761-8BE1-192E68AB0A2F", "firstName": "Kentarou", "lastName": "Miura", "role": "Story & Art" },
          { "id": "0304C4E9-2D89-463A-8FDD-EEAB5B9D57B3", "firstName": "Akira", "lastName": "Toriyama", "role": "Story & Art" }
        ]
        """

        private static let authorsPageJSON = """
        {
          "metadata": { "total": 2, "page": 4, "per": 20 },
          "items": [
            { "id": "6F0B6948-08C4-4761-8BE1-192E68AB0A2F", "firstName": "Kentarou", "lastName": "Miura", "role": "Story & Art" },
            { "id": "0304C4E9-2D89-463A-8FDD-EEAB5B9D57B3", "firstName": "", "lastName": "Studio Gaga", "role": "Art" }
          ]
        }
        """

        private static let dragonMangasJSON = """
        [
          {
            "id": 42, "title": "Dragon Ball", "score": 8.47, "status": "finished",
            "startDate": "1984-11-20T00:00:00Z",
            "authors": [ { "id": "0304C4E9-2D89-463A-8FDD-EEAB5B9D57B3", "firstName": "Akira", "lastName": "Toriyama", "role": "Story & Art" } ],
            "genres": [ { "id": "4312867C-1359-494A-AC46-BADFD2E1D4CD", "genre": "Action" } ],
            "themes": [ { "id": "4394C99F-615B-494A-929E-356A342A95B8", "theme": "Martial Arts" } ],
            "demographics": [ { "id": "CE425E7E-C7CD-42DB-ADE3-1AB9AD16386D", "demographic": "Shounen" } ]
          },
          {
            "id": 43, "title": "Dragon Quest: Dai no Daibouken", "score": 8.21, "status": "finished",
            "startDate": "1989-10-24T00:00:00Z",
            "authors": [], "genres": [], "themes": [], "demographics": []
          }
        ]
        """
    }
}
