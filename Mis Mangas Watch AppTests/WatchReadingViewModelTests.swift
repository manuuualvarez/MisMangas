//
//  WatchReadingViewModelTests.swift
//  Mis Mangas Watch AppTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
@testable import Mis_Mangas_Watch_App
import SwiftData
import Testing

/// Choosing the volume being read on a manga's watch screen: every volume the reader picks is
/// written to the watch's store and sent to the iPhone as one `ReadingUpdate` dated with the
/// change, in the order it was picked, and the stepper follows the store only when the reader has
/// nothing on its way.
///
/// Oracles, never the code under test: the store read back with a fresh `ModelContext` over the
/// in-memory container the real `MangaSyncActor` writes to, the updates the `FakeWatchTransport`
/// captured, the errors it was told to throw, the messages written out by hand, and the volume
/// rules the screens state (from 1 up to the volume count, up to 300 while the count is unknown).
@Suite("WatchReadingViewModel")
@MainActor
struct WatchReadingViewModelTests {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let transport = FakeWatchTransport()
    private let actor: MangaSyncActor
    private let container: ModelContainer

    init() throws {
        let made = try WatchPersistenceTestSupport.makeActor()
        actor = made.actor
        container = made.container
    }

    /// Stores manga 42 in the collection, reading `readingVolume`, changed at `t0`, and opens its
    /// screen's view model as the screen would, from the stored values.
    private func openReading(_ readingVolume: Int, volumes: Int?) throws -> WatchReadingViewModel {
        try WatchPersistenceTestSupport.insertManga(
            id: 42,
            volumes: volumes,
            updatedAt: Self.t0,
            entry: .init(readingVolume: readingVolume, updatedAt: Self.t0),
            in: container
        )
        return makeViewModel(readingVolume: readingVolume, volumes: volumes)
    }

    private func makeViewModel(readingVolume: Int?, volumes: Int?) -> WatchReadingViewModel {
        WatchReadingViewModel(mangaID: 42, readingVolume: readingVolume, volumes: volumes, syncActor: actor, transport: transport)
    }

    /// What the stepper does: moves the draft, then tells the view model.
    private func pick(_ volume: Int, on viewModel: WatchReadingViewModel) {
        viewModel.draft = volume
        viewModel.draftChanged()
    }

    /// Waits until every change asked for has finished.
    private func settle(_ viewModel: WatchReadingViewModel) async {
        let isSettled = await WatchPersistenceTestSupport.waitUntil { !viewModel.isChanging }
        #expect(isSettled)
    }

    private func storedEntry() throws -> UserCollectionEntry {
        let context = WatchPersistenceTestSupport.freshContext(container)
        return try #require(try WatchPersistenceTestSupport.entry(mangaID: 42, in: context))
    }

    // MARK: - Picking a volume

    @Test func `Picking a volume past the last one stores the last and sends it dated with the change`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        pick(50, on: viewModel)
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 42)
        #expect(entry.updatedAt != Self.t0)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 42, sentAt: entry.updatedAt)])
        #expect(viewModel.draft == 42)
        #expect(viewModel.error == nil)
    }

    @Test func `Picking a volume below the first stores the first`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        pick(0, on: viewModel)
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 1)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 1, sentAt: entry.updatedAt)])
    }

    @Test func `Without a known volume count a volume up to the collection limit is stored as it is`() async throws {
        let viewModel = try openReading(7, volumes: nil)

        pick(60, on: viewModel)
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 60)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 60, sentAt: entry.updatedAt)])
    }

    @Test func `Picking the stored volume writes and sends nothing`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        pick(7, on: viewModel)
        await settle(viewModel)

        let untouched = try storedEntry()
        #expect(untouched.updatedAt == Self.t0)
        #expect(transport.sentUpdates.isEmpty)

        // Another volume on the same screen does go through, so the pick above was skipped.
        pick(8, on: viewModel)
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 8)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: entry.updatedAt)])
    }

    // MARK: - Quick picks

    @Test func `Volumes picked in a row reach the store and the iPhone in the order they were picked`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        pick(8, on: viewModel)
        pick(9, on: viewModel)
        pick(10, on: viewModel)
        #expect(viewModel.isChanging)
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 10)
        #expect(transport.sentUpdates.map(\.readingVolume) == [8, 9, 10])
        #expect(transport.sentUpdates.map(\.sentAt) == transport.sentUpdates.map(\.sentAt).sorted())
        #expect(transport.sentUpdates.last?.sentAt == entry.updatedAt)
        #expect(viewModel.draft == 10)
    }

    @Test func `Going back to the stored volume before the first change lands is still written and sent`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        pick(8, on: viewModel)
        pick(7, on: viewModel)
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 7)
        #expect(transport.sentUpdates.map(\.readingVolume) == [8, 7])
        #expect(viewModel.draft == 7)
    }

    // MARK: - Next volume

    @Test func `Marking the next volume read moves one volume forward`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        viewModel.markNextVolumeRead()
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 8)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: entry.updatedAt)])
        #expect(viewModel.draft == 8)
    }

    @Test func `On the last volume marking the next one read neither edits nor sends`() async throws {
        let viewModel = try openReading(41, volumes: 42)
        #expect(!viewModel.isOnLastVolume)

        viewModel.markNextVolumeRead()
        await settle(viewModel)
        #expect(viewModel.isOnLastVolume)

        viewModel.markNextVolumeRead()
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 42)
        #expect(transport.sentUpdates.map(\.readingVolume) == [42])
        #expect(viewModel.draft == 42)
    }

    @Test func `Without a known volume count the next volume is only limited by the collection limit`() async throws {
        let viewModel = try openReading(60, volumes: nil)

        viewModel.markNextVolumeRead()
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 61)
        #expect(transport.sentUpdates.map(\.readingVolume) == [61])
    }

    // MARK: - Changes from the iPhone

    @Test func `A volume stored from the iPhone moves the stepper and is neither written nor sent back`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        viewModel.storedVolumeChanged(12, volumes: 42)
        viewModel.draftChanged()
        await settle(viewModel)

        #expect(viewModel.draft == 12)
        #expect(try storedEntry().updatedAt == Self.t0)
        #expect(transport.sentUpdates.isEmpty)
    }

    @Test func `A volume stored from the iPhone above a smaller volume count is followed without a write`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        viewModel.storedVolumeChanged(20, volumes: 18)
        viewModel.draftChanged()
        await settle(viewModel)

        #expect(viewModel.draft == 20)
        #expect(viewModel.readingVolumeRange == 1 ... 18)
        #expect(try storedEntry().updatedAt == Self.t0)
        #expect(transport.sentUpdates.isEmpty)
    }

    @Test func `While the reader's change is on its way the stepper keeps the reader's volume`() async throws {
        let viewModel = try openReading(7, volumes: 42)

        pick(8, on: viewModel)
        // The store reporting the volume it held before the change landed.
        viewModel.storedVolumeChanged(7, volumes: 42)
        #expect(viewModel.draft == 8)
        await settle(viewModel)

        #expect(viewModel.draft == 8)
        #expect(try storedEntry().readingVolume == 8)
        #expect(transport.sentUpdates.map(\.readingVolume) == [8])
    }

    // MARK: - Failures

    @Test func `A send failure is reported and the change stays on the watch`() async throws {
        let viewModel = try openReading(7, volumes: 42)
        transport.configure { $0.sendError = .notActivated }

        pick(8, on: viewModel)
        await settle(viewModel)

        guard case .notActivated? = viewModel.error as? WatchTransportError else {
            Issue.record("Expected WatchTransportError.notActivated, got \(String(describing: viewModel.error))")
            return
        }
        #expect(viewModel.errorMessage == "Couldn't send the change to your iPhone")
        #expect(viewModel.draft == 8)
        let entry = try storedEntry()
        #expect(entry.readingVolume == 8)
        #expect(entry.updatedAt != Self.t0)
        #expect(transport.sentUpdates.isEmpty)
    }

    @Test func `A volume that cannot be stored is reported, sends nothing and the stepper goes back`() async throws {
        try WatchPersistenceTestSupport.insertManga(id: 42, volumes: 42, updatedAt: Self.t0, entry: nil, in: container)
        let viewModel = makeViewModel(readingVolume: 7, volumes: 42)

        pick(8, on: viewModel)
        await settle(viewModel)

        guard case .notFound? = viewModel.error as? PersistenceError else {
            Issue.record("Expected PersistenceError.notFound, got \(String(describing: viewModel.error))")
            return
        }
        #expect(viewModel.errorMessage == "Couldn't change the volume")
        #expect(viewModel.draft == 7)
        #expect(transport.sentUpdates.isEmpty)
        #expect(try WatchPersistenceTestSupport.entryMangaIDs(in: container).isEmpty)
    }

    @Test func `A success after a failure clears the error`() async throws {
        let viewModel = try openReading(7, volumes: 42)
        transport.configure { $0.sendError = .notActivated }
        pick(8, on: viewModel)
        await settle(viewModel)
        try #require(viewModel.error != nil)

        transport.configure { $0.sendError = nil }
        pick(9, on: viewModel)
        await settle(viewModel)

        #expect(viewModel.error == nil)
        #expect(viewModel.errorMessage == nil)
        let entry = try storedEntry()
        #expect(entry.readingVolume == 9)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 9, sentAt: entry.updatedAt)])
    }
}
