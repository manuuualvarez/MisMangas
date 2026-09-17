//
//  CatalogFilterDraft.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 17/09/2026.
//

/// The filter form as the reader edits it. One category at a time: every `/list/mangaBy…`
/// endpoint filters by a single genre, theme or demographic (combining them is the advanced
/// search), so choosing a value in one picker returns the other two to "Any".
struct CatalogFilterDraft {
    var genre: String? {
        didSet {
            if genre != nil {
                theme = nil
                demographic = nil
            }
        }
    }

    var theme: String? {
        didSet {
            if theme != nil {
                genre = nil
                demographic = nil
            }
        }
    }

    var demographic: String? {
        didSet {
            if demographic != nil {
                genre = nil
                theme = nil
            }
        }
    }

    /// Opens on the category `mode` filters by; on "Any" everywhere for every other mode.
    init(mode: CatalogMode) {
        switch mode {
        case .byGenre(let name):
            genre = name
        case .byTheme(let name):
            theme = name
        case .byDemographic(let name):
            demographic = name
        case .all, .best, .byAuthor, .titleContains, .beginsWith, .search:
            break
        }
    }

    /// The mode the catalog shows after applying the form over `current`: the chosen category;
    /// with "Any" everywhere, `.all` when `current` was a filter, or `current` itself (All / Best).
    func applied(to current: CatalogMode) -> CatalogMode {
        if let genre {
            return .byGenre(genre)
        }
        if let theme {
            return .byTheme(theme)
        }
        if let demographic {
            return .byDemographic(demographic)
        }
        return current.isFiltered ? .all : current
    }
}
