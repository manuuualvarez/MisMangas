//
//  EmptyStorePreviewContainer.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftData
import SwiftUI

/// `#Preview(traits: .emptyStore)` on the watch: an empty in-memory store, as after a reading
/// list with nothing being read.
struct EmptyStorePreviewContainer: PreviewModifier {
    static func makeSharedContext() async throws -> ModelContainer {
        try PersistenceController.makeInMemoryContainer()
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var emptyStore: PreviewTrait<Preview.ViewTraits> {
        .modifier(EmptyStorePreviewContainer())
    }
}
