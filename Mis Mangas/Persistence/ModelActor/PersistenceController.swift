//
//  PersistenceController.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData

/// Builds the `ModelContainer` once per process. The app and the widget share the App Group
/// store; the Watch keeps a local one; tests and previews use memory.
enum PersistenceController {
    static let appGroupIdentifier = "group.cloud.manuelalvarez.Mis-Mangas"

    static func makeContainer(groupIdentifier: String = appGroupIdentifier) throws(PersistenceError) -> ModelContainer {
        try make(ModelConfiguration(schema: schema, groupContainer: .identifier(groupIdentifier), cloudKitDatabase: .none))
    }

    static func makeInMemoryContainer() throws(PersistenceError) -> ModelContainer {
        try make(ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    static func makeLocalContainer() throws(PersistenceError) -> ModelContainer {
        try make(ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none))
    }

    private static var schema: Schema {
        Schema(versionedSchema: MangaSchemaV1.self)
    }

    private static func make(_ configuration: ModelConfiguration) throws(PersistenceError) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, migrationPlan: MangaMigrationPlan.self, configurations: [configuration])
        } catch {
            throw .containerUnavailable(error)
        }
    }
}
