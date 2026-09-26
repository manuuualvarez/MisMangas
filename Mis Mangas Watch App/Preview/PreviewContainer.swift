//
//  PreviewContainer.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import SwiftData
import SwiftUI

/// `#Preview(traits: .sampleData)` on the watch: an in-memory store with the sample collection,
/// written through the same actor as the app, plus Kingdom being read at volume 5, the one state
/// the sample collection lacks (a volume count still unknown). Screens that edit get
/// `WatchDependencies` over that store; its session is never activated, so a change stays on the
/// watch and the view model reports that it could not be sent.
struct PreviewContainer: PreviewModifier {
    /// Kingdom: in the sample catalog, with no volume count.
    private static let kingdomID = 16765

    static func makeSharedContext() async throws -> ModelContainer {
        let container = try PersistenceController.makeInMemoryContainer()
        let actor = MangaSyncActor(modelContainer: container)
        // One day apart, so sorting by most recently updated has something to order.
        for (offset, entry) in SampleData.collection.enumerated() {
            try await actor.upsertCollectionEntry(from: entry, now: .now.addingTimeInterval(-Double(offset) * 86400))
        }
        if let kingdom = SampleData.mangas.first(where: { $0.id == kingdomID }) {
            try await actor.upsertCollectionEntry(
                from: UserMangaCollectionDTO(id: UUID(), manga: kingdom, volumesOwned: Array(1 ... 5), readingVolume: 5, completeCollection: false),
                now: .now.addingTimeInterval(-Double(SampleData.collection.count) * 86400)
            )
        }
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modelContainer(context)
            .environment(WatchDependencies(container: context, transport: WatchSessionBridge()))
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var sampleData: PreviewTrait<Preview.ViewTraits> {
        .modifier(PreviewContainer())
    }
}
