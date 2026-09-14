//
//  PersistenceControllerTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// The three container factories. Oracles: what a fresh context can store and read back, the
/// `ModelConfiguration` the container actually carries, and the App Group directory the host
/// resolves through `FileManager` (independent of the production literal).
/// Serialized: the App Group and local tests open real stores on disk, and two containers over
/// the same SQLite file at once would be a source of intermittent failures.
@Suite("PersistenceController", .serialized)
struct PersistenceControllerTests {
    /// The group every app-side store must live in.
    private static let groupIdentifier = "group.cloud.manuelalvarez.Mis-Mangas"

    /// Entities the versioned schema must register, by their model names.
    private static let modelNames = ["Manga", "Author", "CatalogEntry", "UserCollectionEntry", "PendingOperation"]

    private static func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    // MARK: - In-memory

    @Test func `In-memory container keeps nothing on disk`() throws {
        let container = try PersistenceController.makeInMemoryContainer()

        let configuration = try #require(container.configurations.first)
        #expect(container.configurations.count == 1)
        #expect(configuration.isStoredInMemoryOnly)
    }

    @Test func `In-memory container registers every model of the schema`() throws {
        let container = try PersistenceController.makeInMemoryContainer()

        let registered = Set(container.schema.entitiesByName.keys)
        #expect(registered.isSuperset(of: Self.modelNames), "Missing: \(Set(Self.modelNames).subtracting(registered))")
    }

    @Test func `In-memory container stores a manga with its author and an index entry`() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let dto = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))
        let author = try #require(dto.authors.first)

        let writer = PersistenceTestSupport.freshContext(container)
        let manga = dto.makeManga()
        let storedAuthor = author.makeAuthor()
        writer.insert(manga)
        writer.insert(storedAuthor)
        manga.authors = [storedAuthor]
        let entry = CatalogEntry(modeKey: "all", ordinal: 0, fetchedAt: .now)
        entry.manga = manga
        writer.insert(entry)
        try writer.save()

        let reader = PersistenceTestSupport.freshContext(container)
        let mangas = try PersistenceTestSupport.fetchAll(Manga.self, in: reader)
        #expect(mangas.map(\.id) == [1])
        #expect(mangas.first?.authors.map(\.lastName) == ["Urasawa"])
        #expect(try PersistenceTestSupport.fetchAll(Author.self, in: reader).count == 1)
        let entries = try PersistenceTestSupport.catalogEntries(modeKey: "all", in: reader)
        #expect(entries.compactMap(\.manga?.title) == ["Monster"])
    }

    @Test func `Two in-memory containers do not share data`() throws {
        let first = try PersistenceController.makeInMemoryContainer()
        let second = try PersistenceController.makeInMemoryContainer()

        let writer = PersistenceTestSupport.freshContext(first)
        writer.insert(CatalogEntry(modeKey: "all", ordinal: 0, fetchedAt: .now))
        try writer.save()

        let reader = PersistenceTestSupport.freshContext(second)
        #expect(try PersistenceTestSupport.fetchAll(CatalogEntry.self, in: reader).isEmpty)
    }

    // MARK: - App Group (configuration smoke test: it creates the real store of the simulator's group container)

    @Test func `App Group container stores under the shared group directory`() throws {
        let groupURL = try #require(
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupIdentifier),
            "The test host must carry the App Group entitlement"
        )

        let container = try PersistenceController.makeContainer()

        let configuration = try #require(container.configurations.first)
        #expect(!configuration.isStoredInMemoryOnly)
        #expect(configuration.groupAppContainerIdentifier == Self.groupIdentifier)
        #expect(Self.standardizedPath(configuration.url).hasPrefix(Self.standardizedPath(groupURL)))
    }

    @Test func `App Group container registers every model of the schema`() throws {
        let container = try PersistenceController.makeContainer()

        let registered = Set(container.schema.entitiesByName.keys)
        #expect(registered.isSuperset(of: Self.modelNames), "Missing: \(Set(Self.modelNames).subtracting(registered))")
    }

    // MARK: - Local (Watch; creates the real default store in the host's Application Support)

    @Test func `Local container stays outside the App Group`() throws {
        let groupURL = try #require(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupIdentifier))

        let container = try PersistenceController.makeLocalContainer()

        let configuration = try #require(container.configurations.first)
        #expect(!configuration.isStoredInMemoryOnly)
        #expect(configuration.groupAppContainerIdentifier == nil)
        #expect(!Self.standardizedPath(configuration.url).hasPrefix(Self.standardizedPath(groupURL)))
    }
}
