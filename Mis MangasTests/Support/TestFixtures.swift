//
//  TestFixtures.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation

/// Loads JSON fixtures captured from the real backend, resolved relative to this file
/// (`Mis MangasTests/Support/` → `Mis MangasTests/Resources/`), never via `Bundle` lookups.
enum TestFixtures {
    struct MissingFixture: Error, CustomStringConvertible {
        let path: String
        var description: String {
            "Fixture not found at \(path)"
        }
    }

    static func data(_ name: String) throws -> Data {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent() // Support/
            .deletingLastPathComponent() // Mis MangasTests/
            .appending(path: "Resources")
            .appending(path: name)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw MissingFixture(path: path)
        }
        return try Data(contentsOf: url)
    }
}
