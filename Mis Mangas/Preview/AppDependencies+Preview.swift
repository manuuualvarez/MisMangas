//
//  AppDependencies+Preview.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData

extension AppDependencies {
    /// The preview container (already in the environment as the model container) and a catalog
    /// repository that answers from `SampleData` with the given behaviors (`themes` governs
    /// `/list/themes` alone).
    static func preview(
        container: ModelContainer,
        catalog: PreviewMangaRepository.Behavior = .sample,
        themes: PreviewMangaRepository.Behavior = .sample
    ) -> AppDependencies {
        AppDependencies(container: container, mangaRepository: PreviewMangaRepository(behavior: catalog, themes: themes))
    }
}
