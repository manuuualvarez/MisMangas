//
//  CatalogMode.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Which server list the catalog shows. `modeKey` is the value stored in `CatalogEntry`.
enum CatalogMode: Hashable {
    case all
    case best
    case byGenre(String)
    case byTheme(String)
    case byDemographic(String)
    case byAuthor(id: UUID, name: String)
    /// Paginated results of a submitted title search.
    case titleContains(String)
    /// Title suggestions while typing. Not paginated by the server; the service keeps the first few.
    case beginsWith(String)
    case search(CustomSearch)

    var modeKey: String {
        switch self {
        case .all: "all"
        case .best: "best"
        case .byGenre(let genre): "genre:\(genre)"
        case .byTheme(let theme): "theme:\(theme)"
        case .byDemographic(let demographic): "demographic:\(demographic)"
        case .byAuthor(let id, _): "author:\(id.uuidString)"
        case .titleContains(let query): "contains:\(query)"
        case .beginsWith(let query): "begins:\(query)"
        case .search(let search): "search:\(Self.searchKey(search))"
        }
    }

    var title: String {
        switch self {
        case .all: String(localized: "Catalog")
        case .best: String(localized: "Best rated")
        case .byGenre(let name), .byTheme(let name), .byDemographic(let name): name
        case .byAuthor(_, let name): name
        case .titleContains(let query): String(localized: "Results for “\(query)”")
        case .beginsWith: String(localized: "Suggestions")
        case .search: String(localized: "Advanced search")
        }
    }

    /// `true` for every mode other than the two catalog listings, so a screen can offer
    /// "Clear filter" and say "No results" when the mode comes back empty.
    var isFiltered: Bool {
        switch self {
        case .all, .best: false
        case .byGenre, .byTheme, .byDemographic, .byAuthor, .titleContains, .beginsWith, .search: true
        }
    }

    /// Field-by-field key of a search. Index rows outlive the launch that wrote them, so the key
    /// comes from the values themselves and not from `hashValue`, which is seeded per process.
    private static func searchKey(_ search: CustomSearch) -> String {
        [
            search.searchTitle ?? "",
            search.searchAuthorFirstName ?? "",
            search.searchAuthorLastName ?? "",
            search.searchGenres?.joined(separator: ",") ?? "",
            search.searchThemes?.joined(separator: ",") ?? "",
            search.searchDemographics?.joined(separator: ",") ?? "",
            search.searchContains ? "contains" : "begins",
        ].joined(separator: "|")
    }
}
