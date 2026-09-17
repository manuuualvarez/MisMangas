//
//  MangaSchemaV1.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData

/// First schema version. It already contains the collection and outbox models, so later
/// features add data without a migration.
enum MangaSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [
        Manga.self,
        Author.self,
        CatalogEntry.self,
        UserCollectionEntry.self,
        PendingOperation.self
    ]
}
