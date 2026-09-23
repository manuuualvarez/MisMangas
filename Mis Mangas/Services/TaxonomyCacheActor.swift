//
//  TaxonomyCacheActor.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 22/09/2026.
//

/// The three classification lists for the whole session, shared by every screen that asks for
/// them. Keeps each list once it arrives, requests only the ones still missing, and makes a call
/// that arrives while another is loading wait for that one instead of requesting again.
actor TaxonomyCacheActor {
    private let mangaRepository: any MangaRepository
    private var catalog: TaxonomyCatalog = .empty
    /// The load in flight, if any; a call that arrives meanwhile awaits it.
    private var inFlight: Task<(catalog: TaxonomyCatalog, error: APIError?), Never>?

    init(mangaRepository: any MangaRepository) {
        self.mangaRepository = mangaRepository
    }

    /// The lists as they stand after loading the missing ones, and the error of the first list
    /// that failed (`nil` once all three have arrived). The three go out in parallel on the
    /// first call; after a partial failure the next call asks only for the lists that failed.
    /// The requests run in their own task: cancelling the caller does not abort them.
    func load() async -> (catalog: TaxonomyCatalog, error: APIError?) {
        if let inFlight {
            return await inFlight.value
        }
        guard catalog.genres.isEmpty || catalog.themes.isEmpty || catalog.demographics.isEmpty else {
            return (catalog, nil)
        }
        // The load clears itself in the same actor step that stores the lists, so a pending
        // task always means a load in progress. Its body cannot start before the assignment:
        // it runs on this actor, which this call holds until it awaits.
        let task = Task {
            defer { inFlight = nil }
            return await fetchMissing()
        }
        inFlight = task
        return await task.value
    }

    private func fetchMissing() async -> (catalog: TaxonomyCatalog, error: APIError?) {
        let current = catalog
        let repository = mangaRepository
        // The closures spell their error type: a bare `try` would be inferred as untyped.
        async let genres = Self.list(current.genres) { () async throws(APIError) in
            try await repository.fetchAllGenres()
        }
        async let themes = Self.list(current.themes) { () async throws(APIError) in
            try await repository.fetchAllThemes()
        }
        async let demographics = Self.list(current.demographics) { () async throws(APIError) in
            try await repository.fetchAllDemographics()
        }
        let loaded = await (genres, themes, demographics)
        catalog = TaxonomyCatalog(
            genres: Self.values(loaded.0),
            themes: Self.values(loaded.1),
            demographics: Self.values(loaded.2)
        )
        return (catalog, [loaded.0, loaded.1, loaded.2].compactMap(Self.failure).first)
    }

    /// Keeps `existing` when it has content; otherwise runs `fetch` and captures its outcome.
    private static func list(
        _ existing: [String],
        fetch: () async throws(APIError) -> [String]
    ) async -> Result<[String], APIError> {
        guard existing.isEmpty else {
            return .success(existing)
        }
        do throws(APIError) {
            return try .success(await fetch())
        } catch {
            return .failure(error)
        }
    }

    private static func values(_ result: Result<[String], APIError>) -> [String] {
        if case let .success(values) = result { values } else { [] }
    }

    private static func failure(_ result: Result<[String], APIError>) -> APIError? {
        if case let .failure(error) = result { error } else { nil }
    }
}
