//
//  AppDependencies+Preview.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData

extension AppDependencies {
    /// The preview container (already in the environment as the model container), a catalog
    /// repository that answers from `SampleData` with the given behaviors (`themes` governs
    /// `/list/themes` alone) and an account backend that answers sign-in and sign-up as `security`.
    static func preview(
        container: ModelContainer,
        catalog: PreviewMangaRepository.Behavior = .sample,
        themes: PreviewMangaRepository.Behavior = .sample,
        security: PreviewSecurity.Behavior = .accepts
    ) -> AppDependencies {
        AppDependencies(
            container: container,
            mangaRepository: PreviewMangaRepository(behavior: catalog, themes: themes),
            security: PreviewSecurity(behavior: security)
        )
    }
}
