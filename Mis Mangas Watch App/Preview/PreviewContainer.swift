//
//  PreviewContainer.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftData
import SwiftUI

/// `#Preview(traits: .sampleData)` on the watch: an in-memory store with the sample collection,
/// written through the same actor as the app. The watch has no network layer or session, so
/// the store is all a preview needs.
struct PreviewContainer: PreviewModifier {
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try PersistenceController.makeInMemoryContainer()
        let actor = MangaSyncActor(modelContainer: container)
        // One day apart, so sorting by most recently updated has something to order.
        for (offset, entry) in SampleData.collection.enumerated() {
            try await actor.upsertCollectionEntry(from: entry, now: .now.addingTimeInterval(-Double(offset) * 86400))
        }
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var sampleData: PreviewTrait<Preview.ViewTraits> {
        .modifier(PreviewContainer())
    }
}
