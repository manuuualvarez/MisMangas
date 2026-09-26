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
/// captured behind a real `WatchSessionCoordinator` whose session is activated, the errors the fake
/// was told to throw, the messages written out by hand, and the volume rules the screens state
/// (from 1 up to the volume count, up to 300 while the count is unknown).
///
/// A class only for `deinit`, which ends the fake's event stream so the coordinator stops listening.
@Suite("WatchReadingViewModel", .timeLimit(.minutes(1)))
@MainActor
final class WatchReadingViewModelTests {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let transport: FakeWatchTransport
    private let actor: MangaSyncActor
    private let container: ModelContainer
    private let coordinator: WatchSessionCoordinator

    init() throws {
        let made = try WatchPersistenceTestSupport.makeActor()
        let transport = FakeWatchTransport()
        self.transport = transport
        actor = made.actor
        container = made.container
        coordinator = WatchSessionCoordinator(transport: transport, syncActor: made.actor)
    }

    deinit {
        transport.finish()
    }

    /// Stores manga 42 in the collection, reading `readingVolume`, changed at `t0`, and opens its
    /// screen's view model as the screen would, from the stored values.
    private func openReading(_ readingVolume: Int, volumes: Int?) async throws -> WatchReadingViewModel {
        try WatchPersistenceTestSupport.insertManga(
            id: 42,
            volumes: volumes,
            updatedAt: Self.t0,
            entry: .init(readingVolume: readingVolume, updatedAt: Self.t0),
            in: container
        )
        return try await makeViewModel(readingVolume: readingVolume, volumes: volumes)
    }

    /// The view model over a coordinator whose session is already activated, so every change it
    /// sends reaches the fake at once.
    private func makeViewModel(readingVolume: Int?, volumes: Int?) async throws -> WatchReadingViewModel {
        try await activateSession()
        return WatchReadingViewModel(mangaID: 42, readingVolume: readingVolume, volumes: volumes, syncActor: actor, coordinator: coordinator)
    }

    /// Starts the coordinator, delivers `.activated` and returns once the coordinator has taken
    /// it: `receivePendingContent()` only returns with the session activated and nothing pending.
    private func activateSession() async throws {
        await coordinator.start()
        transport.emit(.activated(isReachable: true))
        let activation = ActivationWait()
        let coordinator = self.coordinator
        let task = Task {
            await coordinator.receivePendingContent()
            await activation.markDone()
        }
        let isActivated = await WatchPersistenceTestSupport.waitUntil { await activation.isDone }
        task.cancel()
        try #require(isActivated)
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
        let viewModel = try await openReading(7, volumes: 42)

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
        let viewModel = try await openReading(7, volumes: 42)

        pick(0, on: viewModel)
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 1)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 1, sentAt: entry.updatedAt)])
    }

    @Test func `Without a known volume count a volume up to the collection limit is stored as it is`() async throws {
        let viewModel = try await openReading(7, volumes: nil)

        pick(60, on: viewModel)
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 60)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 60, sentAt: entry.updatedAt)])
    }

    @Test func `Picking the stored volume writes and sends nothing`() async throws {
        let viewModel = try await openReading(7, volumes: 42)

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
        let viewModel = try await openReading(7, volumes: 42)

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
        let viewModel = try await openReading(7, volumes: 42)

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
        let viewModel = try await openReading(7, volumes: 42)

        viewModel.markNextVolumeRead()
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 8)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: entry.updatedAt)])
        #expect(viewModel.draft == 8)
    }

    @Test func `On the last volume marking the next one read neither edits nor sends`() async throws {
        let viewModel = try await openReading(41, volumes: 42)
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
        let viewModel = try await openReading(60, volumes: nil)

        viewModel.markNextVolumeRead()
        await settle(viewModel)

        let entry = try storedEntry()
        #expect(entry.readingVolume == 61)
        #expect(transport.sentUpdates.map(\.readingVolume) == [61])
    }

    // MARK: - Changes from the iPhone

    @Test func `A volume stored from the iPhone moves the stepper and is neither written nor sent back`() async throws {
        let viewModel = try await openReading(7, volumes: 42)

        viewModel.storedVolumeChanged(12, volumes: 42)
        viewModel.draftChanged()
        await settle(viewModel)

        #expect(viewModel.draft == 12)
        #expect(try storedEntry().updatedAt == Self.t0)
        #expect(transport.sentUpdates.isEmpty)
    }

    @Test func `A volume stored from the iPhone above a smaller volume count is followed without a write`() async throws {
        let viewModel = try await openReading(7, volumes: 42)

        viewModel.storedVolumeChanged(20, volumes: 18)
        viewModel.draftChanged()
        await settle(viewModel)

        #expect(viewModel.draft == 20)
        #expect(viewModel.readingVolumeRange == 1 ... 18)
        #expect(try storedEntry().updatedAt == Self.t0)
        #expect(transport.sentUpdates.isEmpty)
    }

    @Test func `While the reader's change is on its way the stepper keeps the reader's volume`() async throws {
        let viewModel = try await openReading(7, volumes: 42)

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
        let viewModel = try await openReading(7, volumes: 42)
        transport.configure { $0.sendError = .payloadTooLarge }

        pick(8, on: viewModel)
        await settle(viewModel)

        guard case .payloadTooLarge? = viewModel.error as? WatchTransportError else {
            Issue.record("Expected WatchTransportError.payloadTooLarge, got \(String(describing: viewModel.error))")
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
        let viewModel = try await makeViewModel(readingVolume: 7, volumes: 42)

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
        let viewModel = try await openReading(7, volumes: 42)
        transport.configure { $0.sendError = .payloadTooLarge }
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

    @Test func `A change the session refuses as not activated is not reported and reaches the iPhone once it activates again`() async throws {
        let viewModel = try await openReading(7, volumes: 42)
        // The session went inactive and the coordinator has not been told yet.
        transport.configure { $0.sendError = .notActivated }

        pick(8, on: viewModel)
        await settle(viewModel)

        #expect(viewModel.error == nil)
        #expect(viewModel.errorMessage == nil)
        #expect(transport.sentUpdates.isEmpty)

        transport.configure { $0.sendError = nil }
        transport.emit(.activated(isReachable: true))

        let isSent = await WatchPersistenceTestSupport.waitUntil { !self.transport.sentUpdates.isEmpty }
        #expect(isSent)
        let entry = try storedEntry()
        #expect(entry.readingVolume == 8)
        #expect(transport.sentUpdates == [ReadingUpdate(mangaID: 42, readingVolume: 8, sentAt: entry.updatedAt)])
    }

    // MARK: - Adjusting with VoiceOver

    @Test func `Incrementing in the middle of the range moves one volume forward`() async throws {
        let viewModel = try await openReading(7, volumes: 42)

        viewModel.incrementDraft()

        #expect(viewModel.draft == 8)
    }

    @Test func `Decrementing in the middle of the range moves one volume back`() async throws {
        let viewModel = try await openReading(7, volumes: 42)

        viewModel.decrementDraft()

        #expect(viewModel.draft == 6)
    }

    @Test func `Incrementing never goes past the last volume`() async throws {
        let viewModel = try await openReading(41, volumes: 42)

        viewModel.incrementDraft()
        #expect(viewModel.draft == 42)

        viewModel.incrementDraft()
        #expect(viewModel.draft == 42)
    }

    @Test func `Decrementing never goes below the first volume`() async throws {
        let viewModel = try await openReading(2, volumes: 42)

        viewModel.decrementDraft()
        #expect(viewModel.draft == 1)

        viewModel.decrementDraft()
        #expect(viewModel.draft == 1)
    }

    @Test func `Without a known volume count incrementing is only limited by the collection limit`() async throws {
        let viewModel = try await openReading(299, volumes: nil)

        viewModel.incrementDraft()
        #expect(viewModel.draft == 300)

        viewModel.incrementDraft()
        #expect(viewModel.draft == 300)
    }
}

/// Records that the coordinator's activation, awaited on another task, has been taken.
private actor ActivationWait {
    private(set) var isDone = false

    func markDone() {
        isDone = true
    }
}
