//
//  CustomSearch+Normalized.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 27/09/2026.
//

extension CustomSearch {
    /// The blank form: no criteria, "begins with" matching.
    static let empty = CustomSearch(
        searchTitle: nil,
        searchAuthorFirstName: nil,
        searchAuthorLastName: nil,
        searchGenres: nil,
        searchThemes: nil,
        searchDemographics: nil,
        searchContains: false
    )

    /// The form as it goes on the wire: blank strings and empty arrays become absent, because
    /// the server combines every present field with AND and an empty set would match nothing.
    var normalized: CustomSearch {
        CustomSearch(
            searchTitle: Self.present(searchTitle),
            searchAuthorFirstName: Self.present(searchAuthorFirstName),
            searchAuthorLastName: Self.present(searchAuthorLastName),
            searchGenres: Self.present(searchGenres),
            searchThemes: Self.present(searchThemes),
            searchDemographics: Self.present(searchDemographics),
            searchContains: searchContains
        )
    }

    private static func present(_ text: String?) -> String? {
        guard let text, text.contains(where: { !$0.isWhitespace }) else {
            return nil
        }
        return text
    }

    private static func present(_ values: [String]?) -> [String]? {
        guard let values, !values.isEmpty else {
            return nil
        }
        return values
    }
}
