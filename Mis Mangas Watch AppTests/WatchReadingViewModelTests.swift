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

/// Changing the volume being read on the watch: the change is written to the watch's store and
/// sent to the iPhone as one `ReadingUpdate` dated with the change.
///
/// Oracles, never the code under test: the store read back with a fresh `ModelContext` over the
/// in-memory container the real `MangaSyncActor` writes to, the updates the `FakeWatchTransport`
/// captured, the errors it was told to throw, and the volume rules the screens state (from 1 up to
/// the volume count, with no upper bound while the count is unknown).
@Suite("WatchReadingViewModel")
@MainActor
struct WatchReadingViewModelTests {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let transport: FakeWatchTransport
    private let container: ModelContainer
    private let viewModel: WatchReadingViewModel

    init() throws {
        let made = try WatchPersistenceTestSupport.makeActor()
        let transport = FakeWatchTransport()
        self.transport = transport
        container = made.container
        viewModel = WatchReadingViewModel(syncActor: made.actor, transport: transport)
    }

    /// Stores manga 42 in the collection, reading `readingVolume`, changed at `t0`.
    private func seedReading(_ readingVolume: Int, volumes: Int?) throws {
        try WatchPersistenceTestSupport.insertManga(
            id: 42,
            volumes: volumes,
            updatedAt: Self.t0,
            entry: .init(readingVolume: readingVolume, updatedAt: Self.t0),
            in: container
        )
    }

    private func storedEntry() throws -> UserCollectionEntry {
        let context = WatchPersistenceTestSupport.freshContext(container)
        return try #require(try WatchPersistenceTestSupport.entry(mangaID: 42, in: context))
    }

    // MARK: - Setting the volume

    @Test func `Setting a volume past the last one stores the last and sends it dated with the change`() async throws {
        try seedReading(7, volumes: 42)

        await viewModel.setReadingVolume(50, for: 42, volumes: 42)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 42)
        #expect(entry.updatedAt != Self.t0)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 42, sentAt: entry.updatedAt)])
        #expect(viewModel.error == nil)
    }

    @Test func `Setting a volume below the first stores the first`() async throws {
        try seedReading(7, volumes: 42)

        await viewModel.setReadingVolume(0, for: 42, volumes: 42)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 1)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 1, sentAt: entry.updatedAt)])
    }

    @Test func `Without a known volume count any volume is stored as it is`() async throws {
        try seedReading(7, volumes: nil)

        await viewModel.setReadingVolume(60, for: 42, volumes: nil)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 60)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 60, sentAt: entry.updatedAt)])
    }

    // MARK: - Next volume

    @Test func `Marking the next volume read moves one volume forward`() async throws {
        try seedReading(7, volumes: 42)

        await viewModel.markNextVolumeRead(for: 42, current: 7, volumes: 42)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 8)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: entry.updatedAt)])
    }

    @Test func `Marking the next volume read on the last volume neither edits nor sends`() async throws {
        try seedReading(41, volumes: 42)

        await viewModel.markNextVolumeRead(for: 42, current: 42, volumes: 42)

        let untouched = try storedEntry()
        #expect(untouched.readingVolume == 41)
        #expect(untouched.updatedAt == Self.t0)
        #expect(transport.sentUpdates.isEmpty)

        // The same manga one volume earlier does move, so the call above was stopped by the limit.
        await viewModel.markNextVolumeRead(for: 42, current: 41, volumes: 42)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 42)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 42, sentAt: entry.updatedAt)])
    }

    @Test func `Without a known volume count the next volume has no limit`() async throws {
        try seedReading(60, volumes: nil)

        await viewModel.markNextVolumeRead(for: 42, current: 60, volumes: nil)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 61)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 61, sentAt: entry.updatedAt)])
    }

    // MARK: - Failures

    @Test func `A send failure is reported and the change stays on the watch`() async throws {
        try seedReading(7, volumes: 42)
        transport.configure { $0.sendError = .notActivated }

        await viewModel.setReadingVolume(8, for: 42, volumes: 42)

        guard case .notActivated? = viewModel.error as? WatchTransportError else {
            Issue.record("Expected WatchTransportError.notActivated, got \(String(describing: viewModel.error))")
            return
        }
        let entry = try storedEntry()
        #expect(entry.readingVolume == 8)
        #expect(entry.updatedAt != Self.t0)
        #expect(transport.sentUpdates.isEmpty)
    }

    @Test func `A manga outside the collection is reported as not found and nothing is sent`() async throws {
        try WatchPersistenceTestSupport.insertManga(id: 42, volumes: 42, updatedAt: Self.t0, entry: nil, in: container)

        await viewModel.setReadingVolume(8, for: 42, volumes: 42)

        guard case .notFound? = viewModel.error as? PersistenceError else {
            Issue.record("Expected PersistenceError.notFound, got \(String(describing: viewModel.error))")
            return
        }
        #expect(transport.sentUpdates.isEmpty)
        #expect(try WatchPersistenceTestSupport.entryMangaIDs(in: container).isEmpty)
    }

    @Test func `A success after a failure clears the error`() async throws {
        try seedReading(7, volumes: 42)
        transport.configure { $0.sendError = .notActivated }
        await viewModel.setReadingVolume(8, for: 42, volumes: 42)
        try #require(viewModel.error != nil)

        transport.configure { $0.sendError = nil }
        await viewModel.setReadingVolume(9, for: 42, volumes: 42)

        #expect(viewModel.error == nil)
        let entry = try storedEntry()
        #expect(entry.readingVolume == 9)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 9, sentAt: entry.updatedAt)])
    }
}
