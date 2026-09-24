//
//  CollectionEditorDraft.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Observation

/// The collection form as the reader edits it, before anything reaches the store: the volumes
/// owned, the one being read and whether the collection is complete. Opens with the stored
/// entry when there is one; `validated()` hands the values over in the shape the store expects.
@Observable
@MainActor
final class CollectionEditorDraft {
    var volumesOwned: Set<Int>
    var readingVolume: Int?
    /// Marking the collection complete selects every published volume; deselecting any volume
    /// clears the mark again.
    var completeCollection: Bool {
        didSet {
            if completeCollection, let volumesCount, volumesCount > 0 {
                volumesOwned = Set(1 ... volumesCount)
            }
        }
    }

    /// Published volumes, up to `UserCollectionEntry.volumeLimit`; `nil` while the manga is still
    /// being published, and then the reader types the volumes and the reading volume freely
    /// within that limit.
    let volumesCount: Int?

    /// The reading volume as a stepper drives it: `0` stands for "not started", so one step down
    /// from volume 1 clears it.
    var readingVolumeSelection: Int {
        get { readingVolume ?? 0 }
        set { readingVolume = newValue > 0 ? newValue : nil }
    }

    /// How many volumes are owned, for a manga whose volume count is unknown: typing `n` means
    /// volumes 1…n, and an empty field means none.
    var ownedVolumeCount: Int? {
        get { volumesOwned.isEmpty ? nil : volumesOwned.count }
        set {
            if let newValue, newValue > 0 {
                volumesOwned = Set(1 ... min(newValue, UserCollectionEntry.volumeLimit))
            } else {
                volumesOwned = []
            }
        }
    }

    init(from manga: Manga) {
        volumesCount = manga.volumes.map { min($0, UserCollectionEntry.volumeLimit) }
        let entry = manga.collectionEntry
        volumesOwned = Set(entry?.volumesOwned ?? [])
        readingVolume = entry?.readingVolume
        completeCollection = entry?.completeCollection ?? false
    }

    func toggle(volume: Int) {
        if volumesOwned.contains(volume) {
            volumesOwned.remove(volume)
            completeCollection = false
        } else {
            volumesOwned.insert(volume)
        }
    }

    func toggleComplete() {
        completeCollection.toggle()
    }

    /// The values to save: volumes ascending, and the reading volume kept within 1…`volumesCount`
    /// when the count is known (the server may have lowered it since the entry was stored). A
    /// free reading volume stays within 1…`UserCollectionEntry.volumeLimit`, and 0 or below
    /// means none.
    func validated() -> (volumesOwned: [Int], readingVolume: Int?, completeCollection: Bool) {
        var reading = readingVolume
        if let current = reading, let volumesCount, volumesCount > 0 {
            reading = min(max(current, 1), volumesCount)
        } else if let current = reading {
            reading = current > 0 ? min(current, UserCollectionEntry.volumeLimit) : nil
        }
        return (volumesOwned.sorted(), reading, completeCollection)
    }
}
