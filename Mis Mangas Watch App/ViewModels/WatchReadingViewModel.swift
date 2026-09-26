//
//  WatchReadingViewModel.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Observation
import WatchKit

/// Control state of a manga's watch screen: the volume the reader is choosing, written on the
/// watch and sent to the iPhone.
///
/// Every volume the reader picks becomes one change, and changes run one after another in the
/// order they were picked, so two quick taps never reach the store or the iPhone the other way
/// round. None is cancelled: each one is on screen the moment it is picked, and the last one to
/// run is the reader's last choice. While any is on its way the stepper keeps the reader's
/// volume; once they have all run it shows what the store keeps, which differs only if a change
/// could not be written.
@Observable
@MainActor
final class WatchReadingViewModel {
    /// The volume the reader has chosen; the stepper edits it and `draftChanged()` acts on it.
    var draft: Int
    /// The last failure to change the volume or to send the change; `nil` after a success.
    private(set) var error: (any Error)?

    let mangaID: Int
    private(set) var volumes: Int?

    /// The volume this screen knows the store keeps.
    private var stored: Int?
    /// The volume of the last change asked for, until every change has run.
    private var lastQueued: Int?
    /// The change asked for last: the next one starts when it ends.
    private var lastChange: Task<Void, Never>?
    /// Changes asked for that have not finished yet.
    private var pendingChanges = 0

    private let syncActor: MangaSyncActor
    private let transport: any WatchTransport

    init(mangaID: Int, readingVolume: Int?, volumes: Int?, syncActor: MangaSyncActor, transport: any WatchTransport) {
        self.mangaID = mangaID
        self.volumes = volumes
        stored = readingVolume
        draft = readingVolume ?? 1
        self.syncActor = syncActor
        self.transport = transport
    }

    /// The volumes the reader can pick: from the first to the last, or up to the store's limit
    /// while the count is unknown.
    var readingVolumeRange: ClosedRange<Int> {
        UserCollectionEntry.readingVolumeRange(volumes: volumes)
    }

    var isOnLastVolume: Bool {
        draft >= readingVolumeRange.upperBound
    }

    /// Some change asked for has not finished yet.
    var isChanging: Bool {
        pendingChanges > 0
    }

    /// What the screen says about `error`: the change did not happen on the watch, or it did and
    /// only the iPhone missed it.
    var errorMessage: String? {
        switch error {
        case nil:
            nil
        case is WatchTransportError:
            String(localized: "Couldn't send the change to your iPhone")
        default:
            String(localized: "Couldn't change the volume")
        }
    }

    /// Acts on a new `draft`: a volume other than the one already on its way (or, with nothing on
    /// its way, other than the stored one) is kept within `readingVolumeRange` and queued.
    func draftChanged() {
        guard draft != lastQueued ?? stored else {
            return
        }
        let range = readingVolumeRange
        let volume = min(max(draft, range.lowerBound), range.upperBound)
        if volume != draft {
            draft = volume
        }
        guard volume != lastQueued ?? stored else {
            return
        }
        queue(volume)
    }

    /// Moves the draft one volume on, unless it is already on the last one.
    func markNextVolumeRead() {
        guard !isOnLastVolume else {
            return
        }
        draft += 1
        draftChanged()
    }

    /// What the store now keeps for this manga, as the screen reads it. With nothing of the
    /// reader's on its way the stepper follows it (a change from the iPhone), and following it
    /// never writes or sends anything.
    func storedVolumeChanged(_ volume: Int?, volumes: Int?) {
        self.volumes = volumes
        guard !isChanging else {
            return
        }
        stored = volume
        if let volume {
            draft = volume
        }
    }

    private func queue(_ volume: Int) {
        let previous = lastChange
        lastQueued = volume
        pendingChanges += 1
        lastChange = Task {
            await previous?.value
            await apply(volume)
            pendingChanges -= 1
            if pendingChanges == 0 {
                settle()
            }
        }
    }

    private func apply(_ readingVolume: Int) async {
        let changedAt: Date
        do {
            changedAt = try await syncActor.applyLocalReadingVolume(mangaID: mangaID, readingVolume: readingVolume)
        } catch {
            self.error = error
            WKInterfaceDevice.current().play(.failure)
            return
        }
        stored = readingVolume
        WKInterfaceDevice.current().play(.click)
        do {
            try transport.send(ReadingUpdate(mangaID: mangaID, readingVolume: readingVolume, sentAt: changedAt))
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Every change has run: the stepper shows what the store keeps.
    private func settle() {
        lastQueued = nil
        if let stored, draft != stored {
            draft = stored
        }
    }
}
