//
//  CollectionViewModel.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Observation

/// Control state of the collection editor: whether a write is in flight and the last error.
/// It never holds entries: the detail and the collection tab read them from the store, which
/// `MangaSyncService` writes.
@Observable
@MainActor
final class CollectionViewModel {
    private let syncService: MangaSyncService
    private(set) var isSaving = false
    /// The last failed write; cleared by the next one that succeeds.
    private(set) var error: PersistenceError?
    /// The manga of the last removal that failed, so the list can offer to retry it; cleared by
    /// the next removal that succeeds.
    private(set) var failedRemovalID: Int?

    init(syncService: MangaSyncService) {
        self.syncService = syncService
    }

    func save(mangaID: Int, volumesOwned: [Int], readingVolume: Int?, completeCollection: Bool) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await syncService.saveCollectionEntry(
                mangaID: mangaID,
                volumesOwned: volumesOwned,
                readingVolume: readingVolume,
                completeCollection: completeCollection
            )
            error = nil
        } catch {
            self.error = error
        }
    }

    func remove(mangaID: Int) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await syncService.removeCollectionEntry(mangaID: mangaID)
            error = nil
            failedRemovalID = nil
        } catch {
            self.error = error
            failedRemovalID = mangaID
        }
    }

    /// Repeats the last removal that failed, if any.
    func retryRemoval() async {
        guard let failedRemovalID else {
            return
        }
        await remove(mangaID: failedRemovalID)
    }
}
