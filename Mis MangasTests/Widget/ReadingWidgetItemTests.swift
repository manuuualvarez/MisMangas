//
//  ReadingWidgetItemTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 26/09/2026.
//

@testable import Mis_Mangas
import Testing

/// The texts a reading widget row shows and reads out for one manga. The oracle is the wording the
/// app already uses for the same progress, written out by hand below in the development language:
/// Dragon Ball read up to volume 7, with 42 volumes published or with the count still unknown.
@Suite("ReadingWidgetItem")
struct ReadingWidgetItemTests {
    /// Dragon Ball, reading volume 7, with `volumes` published (`nil` while the count is unknown).
    private static func dragonBall(volumes: Int?) -> ReadingWidgetItem {
        ReadingWidgetItem(id: 42, title: "Dragon Ball", coverFileURL: nil, readingVolume: 7, volumes: volumes)
    }

    @Test(arguments: [
        (42 as Int?, "Vol. 7 of 42"),
        (nil, "Vol. 7"),
    ])
    func `volumeText abbreviates the volume and adds the count when it is known`(volumes: Int?, expected: String) {
        #expect(Self.dragonBall(volumes: volumes).volumeText == expected)
    }

    @Test(arguments: [
        (42 as Int?, "7/42"),
        (nil, "7"),
    ])
    func `shortVolumeText is the bare volume over the count when it is known`(volumes: Int?, expected: String) {
        #expect(Self.dragonBall(volumes: volumes).shortVolumeText == expected)
    }

    @Test(arguments: [
        (42 as Int?, "Dragon Ball, reading volume 7 of 42"),
        (nil, "Dragon Ball, reading volume 7"),
    ])
    func `accessibilityLabel says the title and the reading volume in words`(volumes: Int?, expected: String) {
        #expect(Self.dragonBall(volumes: volumes).accessibilityLabel == expected)
    }
}
