//
//  PageDTODecodingTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

@Suite("PageDTO decoding")
struct PageDTODecodingTests {
    @Test func `First catalog page decodes 20 unique items with a next page`() throws {
        let page = try JSONDecoder.app.decode(PageDTO<MangaDTO>.self, from: TestFixtures.data("mangas_page.json"))

        #expect(page.metadata.total == 64833)
        #expect(page.metadata.page == 1)
        #expect(page.metadata.per == 20)
        #expect(page.items.count == 20)
        #expect(Set(page.items.map(\.id)).count == 20)
    }

    @Test func `Page beyond the total decodes empty without a next page`() throws {
        let page = try JSONDecoder.app.decode(PageDTO<MangaDTO>.self, from: TestFixtures.data("mangas_page_empty.json"))

        #expect(page.items.isEmpty)
        #expect(page.metadata.page == 999_999)
    }

    @Test func `Best mangas page keeps the server order by descending score`() throws {
        let page = try JSONDecoder.app.decode(PageDTO<MangaDTO>.self, from: TestFixtures.data("mangas_page_best.json"))

        #expect(page.items.count == 20)
        #expect(zip(page.items, page.items.dropFirst()).allSatisfy { $0.score >= $1.score })
        #expect(page.items.first?.score == 9.47)
        #expect(page.items.last?.score == 8.89)
    }

    @Test func `Author page decodes items with UUID ids and roles`() throws {
        let json = """
        {
          "metadata": { "total": 2, "page": 1, "per": 20 },
          "items": [
            { "id": "6F0B6948-08C4-4761-8BE1-192E68AB0A2F", "firstName": "Kentarou", "lastName": "Miura", "role": "Story & Art" },
            { "id": "0304C4E9-2D89-463A-8FDD-EEAB5B9D57B3", "firstName": "", "lastName": "Studio Gaga", "role": "Art" }
          ]
        }
        """
        let page = try JSONDecoder.app.decode(PageDTO<AuthorDTO>.self, from: Data(json.utf8))

        #expect(page.metadata.total == 2)
        #expect(page.items.count == 2)
        let first = try #require(page.items.first)
        #expect(first.id == UUID(uuidString: "6F0B6948-08C4-4761-8BE1-192E68AB0A2F"))
        #expect(first.firstName == "Kentarou")
        #expect(first.lastName == "Miura")
        #expect(first.role == .storyAndArt)
        let second = try #require(page.items.last)
        #expect(second.firstName.isEmpty)
        #expect(second.role == .art)
    }
}
