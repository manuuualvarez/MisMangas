//
//  CollectionMappingTests.swift
//  Mis MangasTests
//
//  Created by Manuel Alvarez on 23/09/2026.
//

@testable import Mis_Mangas
import Testing

/// Stored collection entry → request body the server expects, on unmanaged instances (no
/// container). Oracle: literal requests written from the backend contract, where the manga is
/// sent as `manga` (its id), not as `mangaID`.
@Suite("Collection entry to request mapping")
struct CollectionMappingTests {
    @Test(arguments: [(7, false), (nil, true)] as [(Int?, Bool)])
    func `toRequest sends the manga id and the three user fields unchanged`(readingVolume: Int?, isComplete: Bool) {
        let entry = UserCollectionEntry(
            mangaID: 42,
            volumesOwned: [1, 2, 3],
            readingVolume: readingVolume,
            completeCollection: isComplete
        )

        let request = entry.toRequest()

        let expected = UserMangaCollectionRequest(
            manga: 42,
            completeCollection: isComplete,
            volumesOwned: [1, 2, 3],
            readingVolume: readingVolume
        )
        #expect(request == expected)
    }
}
