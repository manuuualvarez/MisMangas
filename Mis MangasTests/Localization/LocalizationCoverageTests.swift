//
//  LocalizationCoverageTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
import Testing

/// Audits the app's real String Catalog in the source tree: English source, complete Spanish
/// translation, no stale keys and plural agreement preserved in Spanish.
@Suite("Localization coverage")
struct LocalizationCoverageTests {
    private struct CatalogNotFound: Error, CustomStringConvertible {
        let path: String
        var description: String {
            "String Catalog not found at \(path)"
        }
    }

    /// Spanish for Spain and for Latin America: both ship, so both must be complete.
    private static let spanishLocales = ["es", "es-419"]
    private static let inflectMarker = "](inflect: true)"

    let catalog: StringCatalog

    init() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent() // Localization/
            .deletingLastPathComponent() // Mis MangasTests/
            .deletingLastPathComponent() // repository root
            .appending(path: "Mis Mangas")
            .appending(path: "Resources")
            .appending(path: "Localizable.xcstrings")
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw CatalogNotFound(path: path)
        }
        catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
    }

    private static func report(_ title: String, _ lines: [String]) -> Comment {
        Comment(rawValue: "\(title) (\(lines.count)):\n" + lines.joined(separator: "\n"))
    }

    @Test("Source language is English")
    func sourceLanguageIsEnglish() {
        #expect(catalog.sourceLanguage == "en")
    }

    @Test("Every translatable key has a complete Spanish translation", arguments: spanishLocales)
    func everyTranslatableKeyHasSpanish(language: String) {
        let missing = catalog.translatableKeys.filter {
            !catalog.isFullyTranslated($0, into: language)
        }
        #expect(missing.isEmpty, Self.report("Keys without a translated \(language) value", missing))
    }

    @Test("The catalog has no stale keys")
    func noStaleKeys() {
        let stale = catalog.strings
            .filter { $0.value.extractionState == "stale" }
            .map(\.key)
            .sorted()
        #expect(stale.isEmpty, Self.report("Stale keys (no longer used in code)", stale))
    }

    @Test("Plural keys keep one/other categories and inflection in Spanish", arguments: spanishLocales)
    func pluralsHaveOneAndOther(language: String) {
        let pluralKeys = catalog.translatableKeys.filter { key in
            if key.contains(Self.inflectMarker) { return true }
            let localizations = catalog.strings[key]?.localizations ?? [:]
            return localizations.values.contains { !$0.pluralTables.isEmpty }
        }
        #expect(!pluralKeys.isEmpty, "Expected at least one key with inflection or plural variations")

        var problems: [String] = []
        for key in pluralKeys {
            guard let localization = catalog.strings[key]?.localizations?[language] else {
                problems.append("\(key) — no \(language) translation")
                continue
            }
            let tables = localization.pluralTables
            for table in tables {
                for category in ["one", "other"] where table[category]?.isFullyTranslated != true {
                    problems.append("\(key) — \(language) plural category '\(category)' missing or not translated")
                }
            }
            // A plural table is an equally valid way to keep agreement; without one, the
            // Spanish value must keep the automatic grammar marker.
            let keepsInflection = localization.stringUnit?.value.contains(Self.inflectMarker) == true
            if key.contains(Self.inflectMarker), tables.isEmpty, !keepsInflection {
                problems.append("\(key) — \(language) value dropped \(Self.inflectMarker)")
            }
        }
        #expect(problems.isEmpty, Self.report("Plural keys without \(language) agreement", problems))
    }
}
