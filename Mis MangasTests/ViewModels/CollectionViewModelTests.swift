//
//  CollectionViewModelTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation
@testable import Mis_Mangas
import SwiftData
import Testing

/// The control state of the collection editor driven through the real local pipeline:
/// ViewModel → `MangaSyncService` → `MangaSyncActor` → store. Nothing here touches the
/// network. The ViewModel never exposes the entry, so the oracle for "what was saved" is a fresh
/// `ModelContext` over the same container, exactly as the detail and the collection tab read
/// it; the other oracles are the fields each test chose to save and `manga_monster.json`.
/// Seeding goes straight through the actor, so a failure here points at the ViewModel.
@Suite("CollectionViewModel")
@MainActor
struct CollectionViewModelTests {
    /// Monster (id 1) as `/search/manga/1` serves it.
    private static let monsterID = 1
    /// An id no fixture carries, so no manga is ever stored under it.
    private static let unknownID = 999

    private let viewModel: CollectionViewModel
    private let actor: MangaSyncActor
    private let container: ModelContainer
    private let monster: MangaDTO

    init() throws {
        let made = try PersistenceTestSupport.makeActor()
        actor = made.actor
        container = made.container
        let repository = DefaultMangaRepositoryTest()
        let service = MangaSyncService(
            syncActor: actor,
            mangaRepository: repository,
            taxonomyCache: TaxonomyCacheActor(mangaRepository: repository)
        )
        viewModel = CollectionViewModel(syncService: service)
        monster = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))
    }

    // MARK: - save

    @Test func `save persists the entry, puts the manga in the collection and ends idle without error`() async throws {
        _ = try await actor.cacheDetail(monster)

        await viewModel.save(
            mangaID: Self.monsterID,
            volumesOwned: Array(1 ... 10),
            readingVolume: 7,
            completeCollection: false
        )

        #expect(!viewModel.isSaving)
        #expect(viewModel.error == nil)
        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.mangaID == Self.monsterID)
        #expect(entry.volumesOwned == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(entry.readingVolume == 7)
        #expect(!entry.completeCollection)
        let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
        #expect(stored.inCollection)
    }

    @Test func `save for a manga that is not stored reports notFound, ends idle and stores nothing`() async throws {
        await viewModel.save(
            mangaID: Self.unknownID,
            volumesOwned: [1],
            readingVolume: nil,
            completeCollection: false
        )

        #expect(!viewModel.isSaving)
        guard case .notFound? = viewModel.error else {
            Issue.record("Expected PersistenceError.notFound, got \(String(describing: viewModel.error))")
            return
        }
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
        #expect(try PersistenceTestSupport.fetchAll(Manga.self, in: context).isEmpty)
    }

    @Test func `A save that succeeds after a failed one clears the error`() async throws {
        await viewModel.save(mangaID: Self.unknownID, volumesOwned: [1], readingVolume: nil, completeCollection: false)
        #expect(viewModel.error != nil)
        _ = try await actor.cacheDetail(monster)

        await viewModel.save(mangaID: Self.monsterID, volumesOwned: [1, 2], readingVolume: 2, completeCollection: false)

        #expect(viewModel.error == nil)
        #expect(!viewModel.isSaving)
        let context = PersistenceTestSupport.freshContext(container)
        let entries = try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context)
        #expect(entries.map(\.mangaID) == [Self.monsterID])
    }

    // MARK: - remove

    @Test func `remove after a save drops the entry and takes the manga out of the collection`() async throws {
        _ = try await actor.cacheDetail(monster)
        await viewModel.save(mangaID: Self.monsterID, volumesOwned: Array(1 ... 10), readingVolume: 7, completeCollection: false)

        await viewModel.remove(mangaID: Self.monsterID)

        #expect(!viewModel.isSaving)
        #expect(viewModel.error == nil)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
        let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))
        #expect(!stored.inCollection)
    }

    @Test func `remove of a manga that was never saved is not an error`() async throws {
        await viewModel.remove(mangaID: Self.unknownID)

        #expect(!viewModel.isSaving)
        #expect(viewModel.error == nil)
        let context = PersistenceTestSupport.freshContext(container)
        #expect(try PersistenceTestSupport.fetchAll(UserCollectionEntry.self, in: context).isEmpty)
    }
}
