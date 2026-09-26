//
//  StringCatalog.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

/// Read-only model of an Xcode String Catalog (`.xcstrings`), decoded from the source tree
/// so tests can audit which keys are translated. Unknown fields (comments, flags) are ignored.
struct StringCatalog: Decodable {
    struct Entry: Decodable {
        let extractionState: String?
        let shouldTranslate: Bool?
        let localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        let stringUnit: StringUnit?
        let variations: Variations?

        /// Every variant nested under this localization (plural and device), one level deep.
        var childVariants: [Localization] {
            Array((variations?.plural ?? [:]).values) + Array((variations?.device ?? [:]).values)
        }

        /// A localization counts as translated only when it reaches at least one string unit
        /// and every reachable string unit is in the `translated` state.
        var isFullyTranslated: Bool {
            let children = childVariants
            guard stringUnit != nil || !children.isEmpty else { return false }
            if let stringUnit, stringUnit.state != "translated" { return false }
            return children.allSatisfy(\.isFullyTranslated)
        }

        /// Every plural table reachable from this localization, including those nested
        /// inside device variants.
        var pluralTables: [[String: Localization]] {
            let own = variations?.plural.map { [$0] } ?? []
            return own + childVariants.flatMap(\.pluralTables)
        }
    }

    struct Variations: Decodable {
        let plural: [String: Localization]?
        let device: [String: Localization]?
    }

    struct StringUnit: Decodable {
        let state: String
        let value: String
    }

    let sourceLanguage: String
    let version: String
    let strings: [String: Entry]

    /// Keys a translator must handle: excludes entries marked "don't translate" and stale ones.
    var translatableKeys: [String] {
        strings
            .filter { $0.value.shouldTranslate != false && $0.value.extractionState != "stale" }
            .map(\.key)
            .sorted()
    }

    func isFullyTranslated(_ key: String, into language: String) -> Bool {
        guard let localization = strings[key]?.localizations?[language] else { return false }
        return localization.isFullyTranslated
    }
}
