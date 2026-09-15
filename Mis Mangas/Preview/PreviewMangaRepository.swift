//
//  PreviewMangaRepository.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

/// Catalog repository for previews: answers the listing endpoints from `SampleData` without a
/// network, or with an empty page or a failure, so a preview can show every screen state.
struct PreviewMangaRepository: MangaRepository {
    enum Behavior {
        case sample
        case empty
        case failure(APIError)
    }

    let behavior: Behavior

    nonisolated init(behavior: Behavior = .sample) {
        self.behavior = behavior
    }

    func fetchMangas(page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.all, page: page, per: per)
    }

    func fetchBestMangas(page: Int, per: Int) async throws(APIError) -> MangaPageDTO {
        try serve(.best, page: page, per: per)
    }

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
}
