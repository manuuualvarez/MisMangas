//
//  BootstrapTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
import Testing

struct BootstrapTests {

    @Test func bundleIdentifierIsCanonical() throws {
        let identifier = try #require(Bundle.main.bundleIdentifier)
        #expect(identifier == "cloud.manuelalvarez.Mis-Mangas")
    }
}
