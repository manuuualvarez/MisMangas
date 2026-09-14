//
//  TaxonomyEnumTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// Oracle: the live taxonomy lists captured in `genres.json`, `themes.json`, `demographics.json`.
/// Every server string must resolve to a real case, so `?? .unknown` only ever fires for new values.
@Suite("Taxonomy enums")
struct TaxonomyEnumTests {
    @Test func `Every live genre resolves to a case other than unknown`() throws {
        let names = try JSONDecoder.app.decode([String].self, from: TestFixtures.data("genres.json"))
        let resolved = names.map { Genre(rawValue: $0) }

        #expect(names.count == 21)
        #expect(resolved.allSatisfy { $0 != nil && $0 != .unknown })
        #expect(Set(resolved).count == names.count)
    }

    @Test func `Every live theme resolves to a case other than unknown`() throws {
        let names = try JSONDecoder.app.decode([String].self, from: TestFixtures.data("themes.json"))
        let resolved = names.map { Theme(rawValue: $0) }

        #expect(names.count == 52)
        #expect(resolved.allSatisfy { $0 != nil && $0 != .unknown })
        #expect(Set(resolved).count == names.count)
    }

    @Test func `Every live demographic resolves to a case other than unknown`() throws {
        let names = try JSONDecoder.app.decode([String].self, from: TestFixtures.data("demographics.json"))
        let resolved = names.map { Demographic(rawValue: $0) }

        #expect(names.count == 5)
        #expect(resolved.allSatisfy { $0 != nil && $0 != .unknown })
        #expect(Set(resolved).count == names.count)
    }

    @Test(arguments: ["Isekai Cooking", "unknown", ""])
    func `A string outside the live taxonomy does not resolve`(raw: String) {
        #expect(Genre(rawValue: raw) == nil)
        #expect(Theme(rawValue: raw) == nil)
        #expect(Demographic(rawValue: raw) == nil)
    }
}
