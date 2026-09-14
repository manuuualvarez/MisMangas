//
//  PreviewContainer.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// `#Preview(traits: .sampleData)`: an in-memory store with `SampleData`. Covers download from the
/// network, as in the app.
struct PreviewContainer: PreviewModifier {
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try PersistenceController.makeInMemoryContainer()
        try SampleData.load(into: ModelContext(container))
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
