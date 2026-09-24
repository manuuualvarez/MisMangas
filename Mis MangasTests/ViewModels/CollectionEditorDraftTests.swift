//
//  CollectionEditorDraftTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation
@testable import Mis_Mangas
import Testing

/// The collection form as the reader edits it, before anything reaches the store: what it opens
/// with, how "complete" and the volume grid drive each other, and which values leave the form
/// when it is saved. Oracles: the literal values each scenario chooses (42 published volumes,
/// volumes 1–10 owned, reading volume 7, …) and, for a manga already in the collection, the
/// entry the actor stored for a real fixture.
@Suite("CollectionEditorDraft")
@MainActor
struct CollectionEditorDraftTests {
    /// Monster (id 1) as `/search/manga/1` serves it: 18 published volumes.
    private static let monsterID = 1
    private static let monsterVolumes = 18

    /// A finished manga with a known number of volumes, never stored: the form only reads its
    /// fields. `nil` volumes is a manga still being published.
    private static func dragonBall(volumes: Int?) -> Manga {
        Manga(id: 42, title: "Dragon Ball", status: "finished", score: 8.4, volumes: volumes)
    }

    // MARK: - Opening the form

    @Test func `Opening the form for a manga with 42 volumes and no entry starts empty`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))

        #expect(draft.volumesOwned.isEmpty)
        #expect(draft.readingVolume == nil)
        #expect(!draft.completeCollection)
        #expect(draft.volumesCount == 42)
    }

    @Test func `Opening the form for a manga in the collection starts with its stored entry`() async throws {
        let (actor, container) = try PersistenceTestSupport.makeActor()
        let monster = try JSONDecoder.app.decode(MangaDTO.self, from: TestFixtures.data("manga_monster.json"))
        _ = try await actor.cacheDetail(monster)
        try await actor.saveCollectionEntry(
            mangaID: Self.monsterID,
            volumesOwned: Array(1 ... 10),
            readingVolume: 7,
            completeCollection: false
        )
        let context = PersistenceTestSupport.freshContext(container)
        let stored = try #require(try PersistenceTestSupport.manga(id: Self.monsterID, in: context))

        let draft = CollectionEditorDraft(from: stored)

        #expect(draft.volumesOwned == Set(1 ... 10))
        #expect(draft.readingVolume == 7)
        #expect(!draft.completeCollection)
        #expect(draft.volumesCount == Self.monsterVolumes)
    }

    // MARK: - Volumes and the complete flag

    @Test func `Toggling a volume selects it and toggling it again deselects it`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))

        draft.toggle(volume: 3)
        #expect(draft.volumesOwned == [3])

        draft.toggle(volume: 3)
        #expect(draft.volumesOwned.isEmpty)
    }

    @Test func `Toggling complete selects every published volume`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))

        draft.toggleComplete()

        #expect(draft.completeCollection)
        #expect(draft.volumesOwned == Set(1 ... 42))
    }

    @Test func `Toggling complete without a volume count only raises the flag`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: nil))
        draft.toggle(volume: 3)

        draft.toggleComplete()

        #expect(draft.completeCollection)
        #expect(draft.volumesOwned == [3])
    }

    @Test func `Deselecting a volume of a complete collection clears the flag and keeps the other volumes`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))
        draft.toggleComplete()

        draft.toggle(volume: 5)

        #expect(!draft.completeCollection)
        #expect(draft.volumesOwned == Set(1 ... 42).subtracting([5]))
    }

    // MARK: - Validation

    @Test(arguments: [
        (0, 1),
        (1, 1),
        (7, 7),
        (42, 42),
        (43, 42),
        (99, 42),
    ] as [(Int, Int)])
    func `validated keeps the reading volume within the published volumes`(reading: Int, expected: Int) {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))
        draft.readingVolume = reading

        #expect(draft.validated().readingVolume == expected)
    }

    @Test func `validated leaves a missing reading volume missing`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))
        draft.readingVolume = nil

        #expect(draft.validated().readingVolume == nil)
    }

    @Test func `validated leaves the reading volume free when the volume count is unknown`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: nil))
        draft.readingVolume = 99

        #expect(draft.validated().readingVolume == 99)
    }

    @Test func `validated hands the form over as the values to save, with the volumes ascending`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))
        draft.toggle(volume: 10)
        draft.toggle(volume: 3)
        draft.toggle(volume: 7)
        draft.readingVolume = 7

        let values = draft.validated()

        #expect(values.volumesOwned == [3, 7, 10])
        #expect(values.readingVolume == 7)
        #expect(!values.completeCollection)
    }

    // MARK: - Control adapters

    @Test(arguments: [
        (nil, 0),
        (7, 7),
    ] as [(Int?, Int)])
    func `The stepper reads 0 for no reading volume and the volume otherwise`(reading: Int?, shown: Int) {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))
        draft.readingVolume = reading

        #expect(draft.readingVolumeSelection == shown)
    }

    @Test(arguments: [
        (3, 3),
        (0, nil),
        (-1, nil),
    ] as [(Int, Int?)])
    func `Stepping to a positive volume sets it and stepping to 0 or below clears it`(stepped: Int, stored: Int?) {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 42))
        draft.readingVolume = 7

        draft.readingVolumeSelection = stepped

        #expect(draft.readingVolume == stored)
    }

    @Test(arguments: [
        ([], nil),
        ([3, 7, 10], 3),
    ] as [(Set<Int>, Int?)])
    func `The volumes field reads empty without volumes and the count otherwise`(owned: Set<Int>, shown: Int?) {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: nil))
        draft.volumesOwned = owned

        #expect(draft.ownedVolumeCount == shown)
    }

    @Test(arguments: [
        (5, Set(1 ... 5)),
        (0, []),
        (nil, []),
        (-2, []),
    ] as [(Int?, Set<Int>)])
    func `Typing a volume count owns volumes 1 through it and an empty or non-positive count owns none`(typed: Int?, owned: Set<Int>) {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: nil))
        draft.toggle(volume: 3)

        draft.ownedVolumeCount = typed

        #expect(draft.volumesOwned == owned)
    }

    // MARK: - Volume limit

    // The form never lets a volume number above 300 through. The longest manga series in print
    // run to about 200 volumes (Kochikame ended at 201), so 300 leaves room for any real
    // collection. Without a limit, a mistyped or pasted count such as 999999999999 builds a set of
    // that many numbers: the app hangs, and a count it survives lands in the shared store, which
    // the collection, the widget and the upload payload then load on every launch.

    @Test func `A typed volume count above 300 owns volumes 1 through 300`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: nil))

        draft.ownedVolumeCount = 100_000

        #expect(draft.volumesOwned == Set(1 ... 300))
    }

    @Test func `Marking complete a manga listed with more than 300 volumes owns volumes 1 through 300`() {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: 100_000))

        draft.toggleComplete()

        #expect(draft.volumesOwned == Set(1 ... 300))
    }

    @Test(arguments: [
        (-3, nil),
        (0, nil),
        (150, 150),
        (300, 300),
        (301, 300),
        (Int.max, 300),
    ] as [(Int, Int?)])
    func `validated keeps a free reading volume between 1 and 300 and clears zero or below`(reading: Int, expected: Int?) {
        let draft = CollectionEditorDraft(from: Self.dragonBall(volumes: nil))
        draft.readingVolume = reading

        #expect(draft.validated().readingVolume == expected)
    }
}
