//
//  WatchReadingViewModel.swift
//  Mis Mangas Watch App
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Observation
import WatchKit

/// Control state of the watch's reading screens: changes the reading volume on the watch and
/// sends the change to the iPhone.
@Observable
@MainActor
final class WatchReadingViewModel {
    /// The last failure to change the volume or to send the change; `nil` after a success.
    private(set) var error: (any Error)?

    private let syncActor: MangaSyncActor
    private let transport: any WatchTransport

    init(syncActor: MangaSyncActor, transport: any WatchTransport) {
        self.syncActor = syncActor
        self.transport = transport
    }

    /// Sets the volume being read, kept between 1 and `volumes` (no upper limit but the store's
    /// while the volume count is unknown), then sends it dated with the change the store made. A
    /// change that cannot be sent stays on the watch; the iPhone's next list decides.
    func setReadingVolume(_ volume: Int, for mangaID: Int, volumes: Int?) async {
        let last = min(volumes ?? UserCollectionEntry.volumeLimit, UserCollectionEntry.volumeLimit)
        let readingVolume = min(max(volume, 1), max(last, 1))
        do {
            let changedAt = try await syncActor.applyLocalReadingVolume(mangaID: mangaID, readingVolume: readingVolume)
            WKInterfaceDevice.current().play(.click)
            try transport.send(ReadingUpdate(mangaID: mangaID, readingVolume: readingVolume, sentAt: changedAt))
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Moves the reading volume one past `current`, unless `current` is already the last volume.
    func markNextVolumeRead(for mangaID: Int, current: Int, volumes: Int?) async {
        if let volumes, current >= volumes {
            return
        }
        await setReadingVolume(current + 1, for: mangaID, volumes: volumes)
    }
}
