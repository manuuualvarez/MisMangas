//
//  PreviewMangaRepository.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Catalog repository for previews: answers every listing, filter, taxonomy, search and author
/// endpoint from `SampleData` without a network, or with an empty result or a failure, so a
/// preview can show every screen state. Detail and author-page endpoints keep their network
/// defaults: no preview uses them.
struct PreviewMangaRepository: MangaRepository {
    enum Behavior {
        case sample
        case empty
        case failure(APIError)
    }

    let behavior: Behavior
    /// Governs `/list/themes` alone, so a preview can show one list failing next to two loaded.
    let themes: Behavior

    nonisolated init(behavior: Behavior = .sample, themes: Behavior = .sample) {
        self.behavior = behavior
        self.themes = themes
    }

    // MARK: - Paginated listings

    func fetchMangas(page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.all, page: page, per: per)
    }

    func fetchBestMangas(page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.best, page: page, per: per)
    }

    func fetchMangasByGenre(_ genre: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.byGenre(genre), page: page, per: per)
    }

    func fetchMangasByTheme(_ theme: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.byTheme(theme), page: page, per: per)
    }

    func fetchMangasByDemographic(_ demographic: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.byDemographic(demographic), page: page, per: per)
    }

    func fetchMangasByAuthor(_ authorID: UUID, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.byAuthor(id: authorID, name: ""), page: page, per: per)
    }

    func searchContains(_ query: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.titleContains(query), page: page, per: per)
    }

    func customSearch(_ search: CustomSearch, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.search(search), page: page, per: per)
    }

    // MARK: - Unpaginated

    func searchBeginsWith(_ query: String) async throws(APIError) -> [MangaDTO] {
        try serve(.beginsWith(query), page: 1, per: SampleData.mangas.count).items
    }

    func searchAuthors(_ query: String) async throws(APIError) -> [AuthorDTO] {
        try list(SampleData.authors(matching: query), as: behavior)
    }

    // MARK: - Taxonomies

    func fetchAllGenres() async throws(APIError) -> [String] {
        try list(SampleData.genres, as: behavior)
    }

    func fetchAllThemes() async throws(APIError) -> [String] {
        try list(SampleData.themes, as: themes)
    }

    func fetchAllDemographics() async throws(APIError) -> [String] {
        try list(SampleData.demographics, as: behavior)
    }

    // MARK: - Private

    private func serve(_ mode: CatalogMode, page: Int, per: Int) throws(APIError) -> MangaPageDTO {
        switch behavior {
        case .sample:
            SampleData.page(for: mode, page: page, per: per)
        case .empty:
            MangaPageDTO(metadata: PageMetadataDTO(total: 0, page: page, per: per), items: [])
        case let .failure(error):
            throw error
        }
    }

    private func list<Element>(_ values: [Element], as behavior: Behavior) throws(APIError) -> [Element] {
        switch behavior {
        case .sample:
            values
        case .empty:
            []
        case let .failure(error):
            throw error
        }
    }
}
