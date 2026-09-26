//
//  CoverCacheFiles.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation

/// Where the reading widget's covers live: one JPEG per manga in a folder the app writes and the
/// widget only reads.
struct CoverCacheFiles {
    let baseURL: URL

    /// The covers folder inside the App Group container; `nil` when the group is not available.
    static let appGroup: CoverCacheFiles? = {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier
        )
        guard let container else {
            return nil
        }
        return CoverCacheFiles(baseURL: container.appending(path: "Library/Caches/covers", directoryHint: .isDirectory))
    }()

    /// The file of `mangaID`'s cover, whether it exists or not.
    func fileURL(for mangaID: Int) -> URL {
        baseURL.appending(path: "\(mangaID).jpg", directoryHint: .notDirectory)
    }

    /// The file of `mangaID`'s cover, only when it exists.
    func existingFileURL(for mangaID: Int) -> URL? {
        let url = fileURL(for: mangaID)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }
}
