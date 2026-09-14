//
//  MangaDTODecodingTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

@Suite("MangaDTO decoding")
struct MangaDTODecodingTests {
    // Oracles computed outside the decoder: UTC midnight as Unix epoch seconds.
    private static let monsterStart = Date(timeIntervalSince1970: 786_585_600) // 1994-12-05
    private static let monsterEnd = Date(timeIntervalSince1970: 1_008_806_400) // 2001-12-20
    private static let ippoStart = Date(timeIntervalSince1970: 622_857_600) // 1989-09-27
    private static let inlineStart = Date(timeIntervalSince1970: 469_756_800) // 1984-11-20

    // MARK: - Real fixtures

    @Test func `Monster fixture decodes every populated field`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))

        #expect(manga.id == 1)
        #expect(manga.title == "Monster")
        #expect(manga.titleEnglish == "Monster")
        #expect(manga.titleJapanese == "MONSTER")
        #expect(manga.synopsis?.hasPrefix("Kenzou Tenma, a renowned Japanese neurosurgeon") == true)
        #expect(manga.background?.hasPrefix("Monster won the Grand Prize") == true)
        #expect(manga.score == 9.15)
        #expect(manga.status == .finished)
        #expect(manga.startDate == Self.monsterStart)
        #expect(manga.endDate == Self.monsterEnd)
        #expect(manga.chapters == 162)
        #expect(manga.volumes == 18)
        #expect(manga.mainPicture == "https://cdn.myanimelist.net/images/manga/3/258224l.jpg")
        #expect(manga.url == "https://myanimelist.net/manga/1/Monster")

        let author = try #require(manga.authors.first)
        #expect(manga.authors.count == 1)
        #expect(author.id == UUID(uuidString: "54BE174C-2FE9-42C8-A842-85D291A6AEDD"))
        #expect(author.firstName == "Naoki")
        #expect(author.lastName == "Urasawa")
        #expect(author.role == .storyAndArt)

        #expect(manga.genres.map(\.genre) == ["Award Winning", "Drama", "Mystery"])
        #expect(manga.themes.map(\.theme) == ["Adult Cast", "Psychological"])
        #expect(manga.demographics.map(\.demographic) == ["Seinen"])
    }

    @Test func `Nulls fixture decodes missing optionals as nil and keeps the rest`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_nulls.json"))

        #expect(manga.endDate == nil)
        #expect(manga.volumes == nil)
        #expect(manga.chapters == nil)
        #expect(manga.titleEnglish == nil)

        #expect(manga.id == 7)
        #expect(manga.title == "Hajime no Ippo")
        #expect(manga.titleJapanese == "はじめの一歩")
        #expect(manga.synopsis?.hasPrefix("Makunouchi Ippo is a 16-year-old") == true)
        #expect(manga.score == 8.71)
        #expect(manga.status == .publishing)
        #expect(manga.startDate == Self.ippoStart)
        #expect(manga.authors.map(\.lastName) == ["Morikawa"])
        #expect(manga.genres.map(\.genre) == ["Award Winning", "Sports"])
        #expect(manga.themes.map(\.theme) == ["Combat Sports"])
        #expect(manga.demographics.map(\.demographic) == ["Shounen"])
    }

    // MARK: - Dates

    @Test(arguments: ["1984-11-20T00:00:00Z", "1984-11-20T00:00:00.000Z"])
    func `ISO 8601 dates decode with and without fractional seconds`(raw: String) throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(startDate: raw))
        #expect(manga.startDate == Self.inlineStart)
    }

    // MARK: - Known API values (captured from the live backend)

    @Test(arguments: [
        ("currently_publishing", MangaStatus.publishing),
        ("finished", MangaStatus.finished),
        ("on_hiatus", MangaStatus.onHiatus),
        ("discontinued", MangaStatus.discontinued),
        ("none", MangaStatus.none),
    ])
    func `Known status strings map to their case`(raw: String, expected: MangaStatus) throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(status: raw))
        #expect(manga.status == expected)
    }

    @Test(arguments: [
        ("Art", AuthorRole.art),
        ("Story", AuthorRole.story),
        ("Story & Art", AuthorRole.storyAndArt),
        ("None", AuthorRole.none),
    ])
    func `Known role strings map to their case`(raw: String, expected: AuthorRole) throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(role: raw))
        let author = try #require(manga.authors.first)
        #expect(author.role == expected)
    }

    // MARK: - Unknown values

    @Test func `Unknown status falls back to none`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(status: "banana"))
        #expect(manga.status == .none)
    }

    @Test func `Unknown author role falls back to none`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(role: "Editor"))
        let author = try #require(manga.authors.first)
        #expect(author.role == .none)
    }

    @Test func `Unknown genre still decodes and keeps the raw string`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(genre: "Isekai Cooking"))
        let genre = try #require(manga.genres.first)
        #expect(genre.genre == "Isekai Cooking")
    }

    @Test func `Unknown theme still decodes and keeps the raw string`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(theme: "Underwater Basket Weaving"))
        let theme = try #require(manga.themes.first)
        #expect(theme.theme == "Underwater Basket Weaving")
    }

    @Test func `Unknown demographic still decodes and keeps the raw string`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(demographic: "Toddlers"))
        let demographic = try #require(manga.demographics.first)
        #expect(demographic.demographic == "Toddlers")
    }

    // MARK: - Minimal inline JSON (shape of `/search/manga/{id}`)

    private static func mangaJSON(
        status: String = "finished",
        role: String = "Story & Art",
        genre: String = "Drama",
        theme: String = "Psychological",
        demographic: String = "Seinen",
        startDate: String = "1984-11-20T00:00:00Z"
    ) -> Data {
        let json = """
        {
          "id": 42,
          "title": "Inline",
          "score": 7.5,
          "status": "\(status)",
          "startDate": "\(startDate)",
          "authors": [
            { "id": "54BE174C-2FE9-42C8-A842-85D291A6AEDD", "firstName": "Naoki", "lastName": "Urasawa", "role": "\(role)" }
          ],
          "genres": [ { "id": "4312867C-1359-494A-AC46-BADFD2E1D4CD", "genre": "\(genre)" } ],
          "themes": [ { "id": "4394C99F-615B-494A-929E-356A342A95B8", "theme": "\(theme)" } ],
          "demographics": [ { "id": "CE425E7E-C7CD-42DB-ADE3-1AB9AD16386D", "demographic": "\(demographic)" } ]
        }
        """
        return Data(json.utf8)
    }
}
