//
//  MangaRepository.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Catalog, search, taxonomy and author endpoints of the backend OpenAPI. All public: no
/// token is attached. Every endpoint is a protocol requirement with a default implementation in
/// the extension, so test doubles and `PreviewMangaRepository` replace any of them through
/// `any MangaRepository` (dynamic dispatch). `Sendable` is required: the existential of a protocol
/// isolated to a global actor is not `Sendable` by itself, and any holder outside `@APIActor`
/// (`MangaSyncService`, tests) sends it to the actor on every call.
protocol MangaRepository: NetworkInteractor, Sendable {
    func fetchMangas(page: Int, per: Int) async throws(APIError) -> MangaPageDTO
    func fetchBestMangas(page: Int, per: Int) async throws(APIError) -> MangaPageDTO
    func fetchMangasByGenre(_ genre: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO
    func fetchMangasByTheme(_ theme: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO
    func fetchMangasByDemographic(_ demographic: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO
    func fetchMangasByAuthor(_ authorID: UUID, page: Int, per: Int) async throws(APIError) -> MangaPageDTO
    func fetchManga(id: Int) async throws(APIError) -> MangaDTO
    func fetchAllGenres() async throws(APIError) -> [String]
    func fetchAllThemes() async throws(APIError) -> [String]
    func fetchAllDemographics() async throws(APIError) -> [String]
    func fetchAuthorsPage(page: Int, per: Int) async throws(APIError) -> AuthorPageDTO
    func fetchAuthors(ids: [UUID]) async throws(APIError) -> [AuthorDTO]
    func searchAuthors(_ query: String) async throws(APIError) -> [AuthorDTO]
    func searchBeginsWith(_ query: String) async throws(APIError) -> [MangaDTO]
    func searchContains(_ query: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO
    func customSearch(_ search: CustomSearch, page: Int, per: Int) async throws(APIError) -> MangaPageDTO
}

/// Production conformer: `URLSession.shared` through the inherited `session` default.
struct DefaultMangaRepository: MangaRepository {
    nonisolated init() {}
}

extension MangaRepository {

    // MARK: - Catalog listings

    func fetchMangas(page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try await getJSON(request: .request(url: .listMangas(page: page, per: per)), type: MangaPageDTO.self)
    }

    func fetchBestMangas(page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try await getJSON(request: .request(url: .listBestMangas(page: page, per: per)), type: MangaPageDTO.self)
    }

    func fetchMangasByGenre(_ genre: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try await getJSON(request: .request(url: .mangaByGenre(genre, page: page, per: per)), type: MangaPageDTO.self)
    }

    func fetchMangasByTheme(_ theme: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try await getJSON(request: .request(url: .mangaByTheme(theme, page: page, per: per)), type: MangaPageDTO.self)
    }

    func fetchMangasByDemographic(_ demographic: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try await getJSON(request: .request(url: .mangaByDemographic(demographic, page: page, per: per)), type: MangaPageDTO.self)
    }

    func fetchMangasByAuthor(_ authorID: UUID, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try await getJSON(request: .request(url: .mangaByAuthor(authorID, page: page, per: per)), type: MangaPageDTO.self)
    }

    // MARK: - Detail

    func fetchManga(id: Int) async throws(APIError) -> MangaDTO {
        try await getJSON(request: .request(url: .mangaByID(id)), type: MangaDTO.self)
    }

    // MARK: - Taxonomies (the API returns plain string arrays)

    func fetchAllGenres() async throws(APIError) -> [String] {
        try await getJSON(request: .request(url: .listGenres), type: [String].self)
    }

    func fetchAllThemes() async throws(APIError) -> [String] {
        try await getJSON(request: .request(url: .listThemes), type: [String].self)
    }

    func fetchAllDemographics() async throws(APIError) -> [String] {
        try await getJSON(request: .request(url: .listDemographics), type: [String].self)
    }

    // MARK: - Authors

    func fetchAuthorsPage(page: Int, per: Int) async throws(APIError) -> AuthorPageDTO {
        try await getJSON(request: .request(url: .listAuthorsPaged(page: page, per: per)), type: AuthorPageDTO.self)
    }

    func fetchAuthors(ids: [UUID]) async throws(APIError) -> [AuthorDTO] {
        let body = AuthorIdsRequest(ids: ids.map(\.uuidString))
        return try await getJSON(request: .request(url: .listAuthorsByIDs, method: .post, body: body), type: [AuthorDTO].self)
    }

    func searchAuthors(_ query: String) async throws(APIError) -> [AuthorDTO] {
        try await getJSON(request: .request(url: .authorSearch(query)), type: [AuthorDTO].self)
    }

    // MARK: - Search

    func searchBeginsWith(_ query: String) async throws(APIError) -> [MangaDTO] {
        try await getJSON(request: .request(url: .mangasBeginsWith(query)), type: [MangaDTO].self)
    }

    func searchContains(_ query: String, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try await getJSON(request: .request(url: .mangasContains(query, page: page, per: per)), type: MangaPageDTO.self)
    }

    func customSearch(_ search: CustomSearch, page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try await getJSON(request: .request(url: .customSearch(page: page, per: per), method: .post, body: search), type: MangaPageDTO.self)
    }
}
