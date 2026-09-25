//
//  EmptyStorePreviewContainer.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// `#Preview(traits: .emptyStore(catalog:))`: an empty in-memory store, for the first-launch
/// states (nothing cached yet: loading, empty result, failure with retry).
struct EmptyStorePreviewContainer: PreviewModifier {
    var catalog: PreviewMangaRepository.Behavior = .empty

    static func makeSharedContext() async throws -> ModelContainer {
        try PersistenceController.makeInMemoryContainer()
    }

    func body(content: Content, context: ModelContainer) -> some View {
        let dependencies = AppDependencies.preview(container: context, catalog: catalog)
        return content
            .modelContainer(context)
            .environment(dependencies)
            .environment(dependencies.session)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static func emptyStore(catalog: PreviewMangaRepository.Behavior = .empty) -> PreviewTrait<Preview.ViewTraits> {
        .modifier(EmptyStorePreviewContainer(catalog: catalog))
    }
}
