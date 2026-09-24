//
//  PersistenceErrorTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// What a store failure tells the user: a fixed message, never the text of the underlying store
/// error, which can carry the container path and the names of tables and constraints. Oracle: a
/// store error whose description is exactly such a path and constraint.
@Suite("PersistenceError")
struct PersistenceErrorTests {
    private struct StoreError: LocalizedError {
        var errorDescription: String? {
            "/private/var/mobile/Containers/Shared/AppGroup/1A2B/default.store: UNIQUE constraint failed: ZMANGA.ZID"
        }
    }

    @Test(arguments: [PersistenceError.saveFailed(StoreError()), .containerUnavailable(StoreError())])
    func `A store failure shows a fixed message without the text of the underlying error`(error: PersistenceError) throws {
        let description = try #require(error.errorDescription)

        #expect(description.contains("AppGroup") == false)
        #expect(description.contains("ZMANGA") == false)
    }
}
