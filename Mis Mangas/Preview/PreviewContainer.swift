//
//  PreviewContainer.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// `#Preview(traits: .sampleData)`: an in-memory store filled with `SampleData` (catalog and
/// collection) through the same actor as the app, plus `AppDependencies` over that store and a
/// `PreviewMangaRepository` whose `catalog` behavior the preview picks (`themes` governs
/// `/list/themes` alone). Covers download from the network, as in the app.
struct PreviewContainer: PreviewModifier {
    var catalog: PreviewMangaRepository.Behavior = .sample
    var themes: PreviewMangaRepository.Behavior = .sample

    static func makeSharedContext() async throws -> ModelContainer {
        let container = try PersistenceController.makeInMemoryContainer()
        let actor = MangaSyncActor(modelContainer: container)
        for mode in [CatalogMode.all, .best] {
            let page = SampleData.page(for: mode, page: 1, per: 20)
            try await actor.replaceCatalogPage(modeKey: mode.modeKey, page: 1, per: 20, dtos: page.items)
        }
        // One day apart, so sorting by most recently updated has something to order.
        for (offset, entry) in SampleData.collection.enumerated() {
            try await actor.upsertCollectionEntry(from: entry, now: .now.addingTimeInterval(-Double(offset) * 86400))
        }
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modelContainer(context)
            .environment(AppDependencies.preview(container: context, catalog: catalog, themes: themes))
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var sampleData: PreviewTrait<Preview.ViewTraits> {
        .modifier(PreviewContainer())
    }

    /// Sample store, but the catalog repository behaves as `catalog` on the next load, and
    /// `/list/themes` as `themes`.
    static func sampleData(
        catalog: PreviewMangaRepository.Behavior,
        themes: PreviewMangaRepository.Behavior = .sample
    ) -> PreviewTrait<Preview.ViewTraits> {
        .modifier(PreviewContainer(catalog: catalog, themes: themes))
    }
}
