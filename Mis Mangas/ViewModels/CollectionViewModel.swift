//
//  CollectionViewModel.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 23/09/2026.
//

import Foundation
import Observation

/// Control state of the collection screens: whether a write or a synchronization is in flight,
/// the last errors, what the queue still holds and what the last pass did. It never holds entries:
/// the detail and the collection tab read them from the store, which `MangaSyncService` writes.
/// Every write is stamped with the account of the session at that moment and followed by a pass;
/// a guest's pass never reaches the network.
@Observable
@MainActor
final class CollectionViewModel {
    private let syncService: MangaSyncService
    private let syncCoordinator: SyncCoordinator
    private let session: SessionViewModel
    private let presentsRejections: Bool
    /// Numbers each reading of the coordinator: readings overlap (a pass ends while the user syncs),
    /// and only the last one issued is shown.
    private var readingSequence = 0
    /// Tells the latest link from one a newer link cancelled, whose ending must not touch the
    /// newer one's state.
    private var deepLinkSequence = 0
    private(set) var isSaving = false
    /// The last failed write; cleared by the next one that succeeds.
    private(set) var error: PersistenceError?
    /// The manga of the last removal that failed, so the list can offer to retry it; cleared by
    /// the next removal that succeeds.
    private(set) var failedRemovalID: Int?
    /// When the last pass that reached the server ended, whichever screen asked for it.
    private(set) var lastSyncDate: Date?
    /// What that pass did.
    private(set) var lastResult: SyncResult?
    /// The mangas whose change the server refused since the collection last showed them.
    private(set) var rejectedMangaIDs: [Int] = []
    private(set) var isSyncing = false
    /// Whether the collection tells the user that the server refused changes; it comes up while
    /// refusals wait to be shown.
    var isRejectionNoticePresented = false
    /// Changes of the session's account, and the guest's, still waiting to reach the server.
    private(set) var pendingCount = 0
    /// Of those, the ones the server kept failing, set aside until retried.
    private(set) var blockedCount = 0
    /// The last synchronization that failed on the device. An expired session is not one: the root
    /// view ends it and returns to the welcome screen.
    private(set) var syncError: SyncError?
    /// Whether the collection shows `syncError`.
    var isSyncErrorPresented = false
    /// Why the manga of the last link could not be opened.
    private(set) var deepLinkError: APIError?
    /// Whether the collection shows `deepLinkError`.
    var isDeepLinkErrorPresented = false
    /// Whether the manga of the last link is being brought from the server.
    private(set) var isOpeningDeepLink = false

    /// `presentsRejections`: whether this screen shows the refusal notice. Only one screen does, so
    /// the notice is never raised where nothing can dismiss it.
    init(
        syncService: MangaSyncService,
        syncCoordinator: SyncCoordinator,
        session: SessionViewModel,
        presentsRejections: Bool = true
    ) {
        self.syncService = syncService
        self.syncCoordinator = syncCoordinator
        self.session = session
        self.presentsRejections = presentsRejections
    }

    func save(mangaID: Int, volumesOwned: [Int], readingVolume: Int?, completeCollection: Bool) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await syncService.saveCollectionEntry(
                mangaID: mangaID,
                volumesOwned: volumesOwned,
                readingVolume: readingVolume,
                completeCollection: completeCollection,
                account: session.account
            )
            error = nil
        } catch {
            self.error = error
            return
        }
        await syncCoordinator.requestSync()
    }

    func remove(mangaID: Int) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await syncService.removeCollectionEntry(mangaID: mangaID, account: session.account)
            error = nil
            failedRemovalID = nil
        } catch {
            self.error = error
            failedRemovalID = mangaID
            return
        }
        await syncCoordinator.requestSync()
    }

    /// Repeats the last removal that failed, if any.
    func retryRemoval() async {
        guard let failedRemovalID else {
            return
        }
        await remove(mangaID: failedRemovalID)
    }

    /// Runs a pass, or joins the one running, and waits for it; then reads what it left.
    func synchronize() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            _ = try await syncCoordinator.synchronize()
            syncError = nil
        } catch {
            present(error)
        }
        await refreshCounts()
    }

    /// Gives the blocked changes a fresh start and waits for the pass that sends them.
    func retryBlocked() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            _ = try await syncCoordinator.retryBlocked()
            syncError = nil
        } catch {
            present(error)
        }
        await refreshCounts()
    }

    /// Reads the queue of the session's account and the last pass in one go, as every screen sees
    /// them. If the store cannot be read, the last reading stays.
    func refreshCounts() async {
        readingSequence += 1
        let reading = readingSequence
        guard let status = try? await syncCoordinator.status(), reading == readingSequence else {
            return
        }
        pendingCount = status.pendingCount
        blockedCount = status.blockedCount
        lastSyncDate = status.lastSyncDate
        lastResult = status.lastResult
        rejectedMangaIDs = status.rejections
        isRejectionNoticePresented = presentsRejections && !rejectedMangaIDs.isEmpty
    }

    /// Keeps the screen current while it is on screen: reads everything now, then again every time
    /// a pass ends, whoever asked for it. Returns when the calling task is cancelled.
    func observePasses() async {
        let events = await syncCoordinator.events()
        await refreshCounts()
        for await event in events {
            if case .passFinished = event {
                await refreshCounts()
            }
        }
    }

    /// Makes sure the store holds the manga of a link, bringing it from the server when it is
    /// missing. Returns whether the collection can show it. A store that cannot be read counts as
    /// not holding it; a cancelled link fails nothing.
    func prepareDeepLinkedManga(id: Int) async -> Bool {
        deepLinkSequence += 1
        let link = deepLinkSequence
        // A newer link ends the wait of the previous one, whether or not it needs the server.
        isOpeningDeepLink = false
        if (try? await syncService.hasManga(id: id)) == true {
            return true
        }
        // Only the latest link shows the wait, the same one its ending clears it for.
        if link == deepLinkSequence {
            isOpeningDeepLink = true
        }
        defer {
            if link == deepLinkSequence {
                isOpeningDeepLink = false
            }
        }
        do {
            try await syncService.refreshDetail(mangaID: id)
        } catch .cancelled {
            return false
        } catch {
            // A failure that arrives once the link was already cancelled is not shown.
            guard !Task.isCancelled else {
                return false
            }
            deepLinkError = error
            isDeepLinkErrorPresented = true
            return false
        }
        return true
    }

    /// Whether the screen offers to sync: only a signed-in session reaches the server.
    var isSyncAvailable: Bool {
        session.isAuthenticated
    }

    /// Where the queue stands, for the announcement that follows a sync the user asked for.
    var syncOutcome: SyncOutcome {
        if blockedCount > 0 {
            return .blocked(blockedCount)
        }
        if pendingCount > 0 {
            return .waiting(pendingCount)
        }
        return .allSynced
    }

    /// What VoiceOver says after a sync the user asked for; nothing while an alert already says
    /// what happened.
    var syncAnnouncement: AttributedString? {
        guard !isSyncErrorPresented, !isRejectionNoticePresented else {
            return nil
        }
        return syncOutcome.announcement
    }

    /// The collection showed the refused changes it read; refusals that arrived since bring the
    /// notice back.
    func acknowledgeRejections() async {
        isRejectionNoticePresented = false
        await syncCoordinator.acknowledgeRejections(rejectedMangaIDs)
        await refreshCounts()
    }

    /// Shows a failure of the device's store. An expired session is the root view's to handle, and
    /// a pass stopped because the session changed is no failure.
    private func present(_ error: SyncError) {
        guard case .persistence(let failure) = error else {
            return
        }
        if case .cancelled = failure {
            return
        }
        syncError = error
        isSyncErrorPresented = true
    }
}
