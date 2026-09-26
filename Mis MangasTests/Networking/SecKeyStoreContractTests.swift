//
//  SecKeyStoreContractTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 24/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// The `SecureStore` contract, run against the real Keychain (`SecKeyStore`) and against the
/// in-memory double every session test relies on, so both keep the same semantics: a written
/// value reads back byte for byte, a second write replaces it, a delete removes only its key,
/// and an absent key reads `nil` and deletes without throwing.
///
/// Each Keychain case uses its own throwaway service, so tests stay independent (and parallel)
/// and never touch the session of the app; the keys it wrote are deleted when it ends.
@Suite("SecureStore contract")
struct SecKeyStoreContractTests {
    enum Implementation: String, CaseIterable, CustomTestStringConvertible {
        case keychain
        case inMemory

        var testDescription: String {
            rawValue
        }

        func makeStore() -> any SecureStore {
            switch self {
            case .keychain:
                SecKeyStore(service: SecKeyStoreContractTests.makeTestService())
            case .inMemory:
                InMemorySecureStore()
            }
        }
    }

    private static let token = Data("header.payload.signature".utf8)
    private static let renewedToken = Data("header.renewed-payload.signature".utf8)
    private static let email = Data("reader@example.com".utf8)

    /// A Keychain service no other test and no app session uses.
    static func makeTestService() -> String {
        "cloud.manuelalvarez.Mis-Mangas.tests.\(UUID().uuidString)"
    }

    /// Runs `body` against a fresh store and deletes the keys the contract uses afterwards, even
    /// when an expectation stops the test early.
    private func withStore(_ implementation: Implementation, _ body: (any SecureStore) throws -> Void) throws {
        let store = implementation.makeStore()
        defer {
            // Cleanup only: a failure here leaves at most two items under a throwaway service.
            _ = try? store.delete("jwt")
            _ = try? store.delete("userEmail")
        }
        try body(store)
    }

    @Test(arguments: Implementation.allCases)
    func `A written value reads back byte for byte`(implementation: Implementation) throws {
        try withStore(implementation) { store in
            try store.write(Self.token, key: "jwt")

            #expect(try store.read("jwt") == Self.token)
        }
    }

    @Test(arguments: Implementation.allCases)
    func `Writing an existing key replaces its value`(implementation: Implementation) throws {
        try withStore(implementation) { store in
            try store.write(Self.token, key: "jwt")
            try store.write(Self.renewedToken, key: "jwt")

            #expect(try store.read("jwt") == Self.renewedToken)
        }
    }

    @Test(arguments: Implementation.allCases)
    func `Deleting a key removes it and keeps the others`(implementation: Implementation) throws {
        try withStore(implementation) { store in
            try store.write(Self.token, key: "jwt")
            try store.write(Self.email, key: "userEmail")
            try #require(try store.read("jwt") == Self.token)

            try store.delete("jwt")

            #expect(try store.read("jwt") == nil)
            #expect(try store.read("userEmail") == Self.email)
        }
    }

    @Test(arguments: Implementation.allCases)
    func `A key never written reads nil and deletes without throwing`(implementation: Implementation) throws {
        try withStore(implementation) { store in
            try store.write(Self.email, key: "userEmail")

            #expect(try store.read("jwt") == nil)
            #expect(throws: Never.self) {
                try store.delete("jwt")
            }
            #expect(try store.read("userEmail") == Self.email)
        }
    }

    @Test func `The Keychain keeps a value across instances of the same service and isolates other services`() throws {
        let service = Self.makeTestService()
        let writer = SecKeyStore(service: service)
        defer {
            // Cleanup only: a failure here leaves one item under a throwaway service.
            _ = try? writer.delete("jwt")
        }

        try writer.write(Self.token, key: "jwt")

        #expect(try SecKeyStore(service: service).read("jwt") == Self.token)
        #expect(try SecKeyStore(service: Self.makeTestService()).read("jwt") == nil)
    }
}
