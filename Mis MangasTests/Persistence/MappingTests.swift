//
//  MappingTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// DTO → `@Model` mapping and the model's display helpers, on unmanaged instances (no container).
/// Oracles: the literal values of the fixtures and the inline JSON, never the DTO fields.
@Suite("DTO to model mapping")
struct MappingTests {
    // Oracles computed outside the decoder: UTC midnight as Unix epoch seconds.
    private static let monsterStart = Date(timeIntervalSince1970: 786_585_600) // 1994-12-05
    private static let monsterEnd = Date(timeIntervalSince1970: 1_008_806_400) // 2001-12-20

    private static func monster() throws -> MangaDTO {
        try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))
    }

    // MARK: - MangaDTO.makeManga

    @Test func `makeManga copies every field of the Monster fixture`() throws {
        let manga = try Self.monster().makeManga()

        #expect(manga.id == 1)
        #expect(manga.title == "Monster")
        #expect(manga.titleEnglish == "Monster")
        #expect(manga.titleJapanese == "MONSTER")
        #expect(manga.synopsis?.hasPrefix("Kenzou Tenma, a renowned Japanese neurosurgeon") == true)
        #expect(manga.background?.hasPrefix("Monster won the Grand Prize") == true)
        #expect(manga.status == "finished")
        #expect(manga.score == 9.15)
        #expect(manga.startDate == Self.monsterStart)
        #expect(manga.endDate == Self.monsterEnd)
        #expect(manga.chapters == 162)
        #expect(manga.volumes == 18)
        #expect(manga.mainPictureURL == "https://cdn.myanimelist.net/images/manga/3/258224l.jpg")
        #expect(manga.url == "https://myanimelist.net/manga/1/Monster")
        #expect(manga.genres == ["Award Winning", "Drama", "Mystery"])
        #expect(manga.themes == ["Adult Cast", "Psychological"])
        #expect(manga.demographics == ["Seinen"])
    }

    @Test func `makeManga leaves the local bookkeeping untouched`() throws {
        let manga = try Self.monster().makeManga()

        #expect(manga.cachedAt == nil)
        #expect(!manga.inCollection)
    }

    @Test func `makeManga keeps nil optionals of the nulls fixture as nil`() throws {
        let dto = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_nulls.json"))

        let manga = dto.makeManga()

        #expect(manga.id == 7)
        #expect(manga.titleEnglish == nil)
        #expect(manga.endDate == nil)
        #expect(manga.chapters == nil)
        #expect(manga.volumes == nil)
        #expect(manga.status == "currently_publishing")
    }

    // MARK: - MangaDTO.apply(to:)

    @Test func `apply refreshes the server fields and keeps the local ones`() throws {
        let original = try Self.monster()
        let manga = original.makeManga()
        let cachedAt = Date(timeIntervalSince1970: 1_700_000_000)
        manga.inCollection = true
        manga.cachedAt = cachedAt
        let updatedAt = manga.updatedAt

        original.replacing(score: 7.5).apply(to: manga)

        #expect(manga.score == 7.5)
        #expect(manga.title == "Monster")
        #expect(manga.genres == ["Award Winning", "Drama", "Mystery"])
        #expect(manga.inCollection)
        #expect(manga.cachedAt == cachedAt)
        #expect(manga.updatedAt == updatedAt)
    }

    // MARK: - AuthorDTO

    @Test func `makeAuthor keeps the id and the role as the API spells it`() throws {
        let dto = try #require(Self.monster().authors.first)

        let author = dto.makeAuthor()

        #expect(author.id == UUID(uuidString: "54BE174C-2FE9-42C8-A842-85D291A6AEDD"))
        #expect(author.firstName == "Naoki")
        #expect(author.lastName == "Urasawa")
        #expect(author.role == "Story & Art")
    }

    @Test func `apply refreshes an author's name and role`() throws {
        let dto = try #require(Self.monster().authors.first)
        let author = dto.makeAuthor()
        let refreshed = AuthorDTO(id: dto.id, firstName: "Naoki", lastName: "Urasawa (浦沢 直樹)", role: .story)

        refreshed.apply(to: author)

        #expect(author.id == dto.id)
        #expect(author.lastName == "Urasawa (浦沢 直樹)")
        #expect(author.role == "Story")
    }

    @Test func `fullName joins the name parts and skips the empty ones`() throws {
        let dto = try #require(Self.monster().authors.first)
        let studio = AuthorDTO(id: UUID(), firstName: "", lastName: "Studio Gaga", role: .art)

        #expect(dto.makeAuthor().fullName == "Naoki Urasawa")
        #expect(studio.makeAuthor().fullName == "Studio Gaga")
    }

    @Test func `roleValue resolves the stored role and falls back to none`() throws {
        let author = try #require(Self.monster().authors.first).makeAuthor()
        #expect(author.roleValue == .storyAndArt)

        author.role = "Editor"

        #expect(author.roleValue == AuthorRole.none)
    }

    // MARK: - Unknown taxonomy values

    @Test func `An unknown status is stored as none and resolves to none`() throws {
        let dto = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(status: "abandoned"))

        let manga = dto.makeManga()

        #expect(manga.status == "none")
        #expect(manga.statusValue == .none)
    }

    @Test func `An unknown genre is stored exactly as it arrived`() throws {
        let dto = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(genre: "Isekai Cooking"))

        let manga = dto.makeManga()

        #expect(manga.genres == ["Isekai Cooking"])
    }

    // MARK: - Display helpers

    @Test(arguments: [
        ("manga_monster.json", MangaStatus.finished),
        ("manga_nulls.json", MangaStatus.publishing),
    ])
    func `statusValue resolves the stored status`(fixture: String, expected: MangaStatus) throws {
        let dto = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data(fixture))

        #expect(dto.makeManga().statusValue == expected)
    }

    @Test func `coverURL parses a valid mainPicture`() throws {
        let manga = try Self.monster().makeManga()

        let cover = try #require(manga.coverURL)
        #expect(cover.host() == "cdn.myanimelist.net")
        #expect(cover.path() == "/images/manga/3/258224l.jpg")
    }

    @Test func `coverURL is nil when the API sends no mainPicture`() throws {
        let dto = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(mainPicture: nil))

        #expect(dto.makeManga().coverURL == nil)
    }

    /// The fixture score (9.15) rendered with two decimals in the test locale, computed here
    /// rather than read back from the model.
    private static var monsterScoreText: String {
        9.15.formatted(.number.precision(.fractionLength(2)))
    }

    @Test func `catalogAccessibilityLabel names the title, the first author and the two-decimal score`() throws {
        let dto = try Self.monster()
        let manga = dto.makeManga()
        manga.authors = dto.authors.map { $0.makeAuthor() }

        #expect(manga.formattedScore == Self.monsterScoreText)
        #expect(manga.catalogAccessibilityLabel == "Monster, by Naoki Urasawa, score \(Self.monsterScoreText)")
    }

    @Test func `publicationAccessibilityLabel says the status and the years in words`() throws {
        let finished = try Self.monster().makeManga()
        #expect(finished.publicationAccessibilityLabel == "Finished, 1994 to 2001")

        let ongoing = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON(status: "currently_publishing")).makeManga()
        #expect(ongoing.publicationAccessibilityLabel == "Publishing, since 1984")

        ongoing.startDate = nil
        #expect(ongoing.publicationAccessibilityLabel == "Publishing")
    }

    @Test func `catalogAccessibilityLabel omits the author part when the manga has no authors`() throws {
        let manga = try Self.monster().makeManga()
        #expect(manga.authors.isEmpty)

        let label = manga.catalogAccessibilityLabel

        #expect(!label.contains(", by "))
        #expect(label == "Monster, score \(Self.monsterScoreText)")
    }

    // MARK: - Inline fixture (shape from the backend OpenAPI)

    private static func mangaJSON(
        status: String = "finished",
        genre: String = "Action",
        mainPicture: String? = "https://cdn.myanimelist.net/images/manga/1/42.jpg"
    ) -> Data {
        let picture = mainPicture.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {
          "id": 42, "title": "Dragon Ball", "score": 8.47, "status": "\(status)",
          "startDate": "1984-11-20T00:00:00Z",
          "mainPicture": \(picture),
          "authors": [ { "id": "0304C4E9-2D89-463A-8FDD-EEAB5B9D57B3", "firstName": "Akira", "lastName": "Toriyama", "role": "Story & Art" } ],
          "genres": [ { "id": "4312867C-1359-494A-AC46-BADFD2E1D4CD", "genre": "\(genre)" } ],
          "themes": [], "demographics": []
        }
        """.utf8)
    }
}
