//
//  MangaMigrationPlan.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData

enum MangaMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [MangaSchemaV1.self]
    static let stages: [MigrationStage] = []
}
