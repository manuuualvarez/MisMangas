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

    // MARK: - Unscored mangas

    /// The backend sends `score: 0` for a manga nobody has rated; an average of 1–10 votes can
    /// never be 0, so the value means "no score" and must never be shown as a real grade.
    private static func unscoredMonster(withAuthor: Bool) throws -> Manga {
        let dto = try Self.monster().replacing(score: 0)
        let manga = dto.makeManga()
        try #require(manga.score == 0)
        if withAuthor {
            manga.authors = dto.authors.map { $0.makeAuthor() }
        }
        return manga
    }

    @Test(arguments: [
        (true, "Monster, by Naoki Urasawa, no score"),
        (false, "Monster, no score"),
    ])
    func `A manga with score 0 reads as unscored, never as a zero grade`(
        withAuthor: Bool,
        expectedCatalogLabel: String
    ) throws {
        let manga = try Self.unscoredMonster(withAuthor: withAuthor)

        #expect(!manga.isScored)
        #expect(manga.formattedScore == "—")
        #expect(manga.scoreAccessibilityLabel == "No score")
        #expect(manga.catalogAccessibilityLabel == expectedCatalogLabel)
        #expect(manga.catalogAccessibilityLabel.hasSuffix(", no score"))
        #expect(!manga.catalogAccessibilityLabel.contains("0"))
    }

    @Test func `A scored manga keeps its two-decimal grade in every label`() throws {
        let dto = try Self.monster()
        let manga = dto.makeManga()
        manga.authors = dto.authors.map { $0.makeAuthor() }

        #expect(manga.isScored)
        #expect(manga.formattedScore == Self.monsterScoreText)
        #expect(manga.scoreAccessibilityLabel == "Score \(Self.monsterScoreText)")
        #expect(manga.catalogAccessibilityLabel.contains("score \(Self.monsterScoreText)"))
    }

    @Test func `attributedJapaneseTitle tags the Japanese title with the Japanese language identifier`() throws {
        let manga = try Self.monster().makeManga()
        manga.titleJapanese = "モンスター"

        let attributed = try #require(manga.attributedJapaneseTitle)

        #expect(String(attributed.characters) == "モンスター")
        #expect(attributed.languageIdentifier == "ja")

        manga.titleJapanese = nil
        #expect(manga.attributedJapaneseTitle == nil)
    }

    // MARK: - Author order

    /// Author ids of Berserk as `mangas_page.json` lists them: Kentarou Miura, then Studio Gaga.
    private static let miuraID = "6F0B6948-08C4-4761-8BE1-192E68AB0A2F"
    private static let studioGagaID = "0304C4E9-2D89-463A-8FDD-EEAB5B9D57B3"

    /// Berserk from the real `/list/mangas` page: the only fixture manga whose API order matters
    /// for the defect, because the second author is a studio credited for the art.
    private static func berserk() throws -> MangaDTO {
        try #require(PersistenceTestSupport.pageItems("mangas_page.json").first { $0.id == 2 })
    }

    @Test func `makeManga stores the author ids in the order the server lists them`() throws {
        let manga = try Self.berserk().makeManga()

        #expect(manga.authorOrder.map(\.uuidString) == [Self.miuraID, Self.studioGagaID])
    }

    @Test func `apply replaces the author order when the server reorders the authors`() throws {
        let dto = try Self.berserk()
        let manga = dto.makeManga()

        dto.replacing(authors: Array(dto.authors.reversed())).apply(to: manga)

        #expect(manga.authorOrder.map(\.uuidString) == [Self.studioGagaID, Self.miuraID])
    }

    /// The relationship array keeps no order, so the same `authors` value is checked against both
    /// orders of `authorOrder`: only honoring `authorOrder` can satisfy the two cases.
    @Test(arguments: [
        ([MappingTests.miuraID, MappingTests.studioGagaID], "Kentarou Miura"),
        ([MappingTests.studioGagaID, MappingTests.miuraID], "Studio Gaga"),
    ])
    func `orderedAuthors and primaryAuthorName follow authorOrder, not the relationship`(
        order: [String],
        expectedPrimary: String
    ) throws {
        let dto = try Self.berserk()
        let manga = dto.makeManga()
        manga.authors = dto.authors.reversed().map { $0.makeAuthor() }
        manga.authorOrder = order.compactMap(UUID.init(uuidString:))
        try #require(manga.authorOrder.count == 2)

        #expect(manga.orderedAuthors.map(\.id.uuidString) == order)
        #expect(manga.primaryAuthorName == expectedPrimary)
        #expect(manga.catalogAccessibilityLabel.contains(", by \(expectedPrimary), "))
    }

    /// A store written before the order existed has an empty or partial `authorOrder`: the
    /// authors it does not list go after the listed ones, alphabetically by full name.
    @Test(arguments: [
        ([MappingTests.studioGagaID], ["Studio Gaga", "Akira Toriyama", "Kentarou Miura"]),
        ([], ["Akira Toriyama", "Kentarou Miura", "Studio Gaga"]),
    ])
    func `orderedAuthors puts the authors missing from authorOrder last, by full name`(
        order: [String],
        expectedNames: [String]
    ) throws {
        let dto = try Self.berserk()
        let manga = dto.makeManga()
        let toriyama = AuthorDTO(id: UUID(), firstName: "Akira", lastName: "Toriyama", role: .storyAndArt)
        manga.authors = (dto.authors + [toriyama]).map { $0.makeAuthor() }
        manga.authorOrder = order.compactMap(UUID.init(uuidString:))
        try #require(manga.authorOrder.count == order.count)

        #expect(manga.orderedAuthors.map(\.fullName) == expectedNames)
        #expect(manga.primaryAuthorName == expectedNames.first)
    }

    // MARK: - Collection row label

    @Test(arguments: [
        (42 as Int?, 7 as Int?, false, "Dragon Ball, reading volume 7 of 42"),
        (nil, 7, false, "Dragon Ball, reading volume 7"),
        (42, 7, true, "Dragon Ball, reading volume 7 of 42, complete collection"),
        (42, nil, true, "Dragon Ball, 3 volumes owned, complete collection"),
        (42, nil, false, "Dragon Ball, 3 volumes owned"),
    ])
    func `collectionAccessibilityLabel says the title and how far the reader has got in words`(
        volumes: Int?, reading: Int?, isComplete: Bool, expected: String
    ) throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON()).makeManga()
        manga.volumes = volumes
        manga.collectionEntry = UserCollectionEntry(
            mangaID: manga.id, volumesOwned: [1, 2, 3], readingVolume: reading, completeCollection: isComplete
        )

        #expect(manga.collectionAccessibilityLabel == expected)
    }

    @Test func `collectionAccessibilityLabel of a single owned volume is singular`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON()).makeManga()
        manga.collectionEntry = UserCollectionEntry(mangaID: manga.id, volumesOwned: [1])

        #expect(manga.collectionAccessibilityLabel == "Dragon Ball, 1 volume owned")
    }

    // MARK: - Collection progress label

    @Test(arguments: [
        (42 as Int?, 7 as Int?, "Reading volume 7 of 42"),
        (nil, 7, "Reading volume 7"),
        (42, nil, "3 volumes owned"),
    ])
    func `collectionProgressAccessibilityLabel spells out the progress the detail abbreviates`(
        volumes: Int?, reading: Int?, expected: String
    ) throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON()).makeManga()
        manga.volumes = volumes
        manga.collectionEntry = UserCollectionEntry(mangaID: manga.id, volumesOwned: [1, 2, 3], readingVolume: reading)

        #expect(manga.collectionProgressAccessibilityLabel == expected)
    }

    @Test func `collectionProgressAccessibilityLabel is nil outside the collection`() throws {
        let manga = try JSONDecoder.app.decode(MangaDTO.self, from: Self.mangaJSON()).makeManga()

        #expect(manga.collectionProgressAccessibilityLabel == nil)
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
