//
//  CustomSearchEncodingTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

@Suite("CustomSearch encoding")
struct CustomSearchEncodingTests {
    @Test func `Encoding with every optional nil keeps searchContains and omits nil keys`() throws {
        let search = CustomSearch(
            searchTitle: nil,
            searchAuthorFirstName: nil,
            searchAuthorLastName: nil,
            searchGenres: nil,
            searchThemes: nil,
            searchDemographics: nil,
            searchContains: true
        )

        let data = try JSONEncoder.app.encode(search)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"searchContains\""))
        #expect(json.contains("true"))
        #expect(!json.contains("\"searchTitle\""))
        #expect(!json.contains("\"searchAuthorFirstName\""))
        #expect(!json.contains("\"searchAuthorLastName\""))
        #expect(!json.contains("\"searchGenres\""))
        #expect(!json.contains("\"searchThemes\""))
        #expect(!json.contains("\"searchDemographics\""))
        #expect(!json.contains("null"))
    }

    @Test func `Round trip with arrays and title preserves equality`() throws {
        let original = CustomSearch(
            searchTitle: "Monster",
            searchAuthorFirstName: nil,
            searchAuthorLastName: "Urasawa",
            searchGenres: ["Drama", "Mystery"],
            searchThemes: ["Psychological"],
            searchDemographics: ["Seinen"],
            searchContains: false
        )

        let data = try JSONEncoder.app.encode(original)
        let decoded = try JSONDecoder.app.decode(CustomSearch.self, from: data)

        #expect(decoded == original)
        #expect(decoded.searchGenres == ["Drama", "Mystery"])
        #expect(decoded.searchContains == false)
    }
}
