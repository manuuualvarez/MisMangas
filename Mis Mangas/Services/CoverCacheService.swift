//
//  CoverCacheService.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 26/09/2026.
//

import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Keeps the reading widget's covers on disk: exactly one small JPEG per manga the widget can show.
/// The widget never downloads; it reads what this service leaves in the shared folder.
actor CoverCacheService {
    /// The longest side of a stored cover, in pixels: a 200 × 280 point cover at 2x.
    private static let maxPixelSize = 560

    private let files: CoverCacheFiles
    private let downloader: ImageDownloader
    private let logger = Logger(subsystem: "cloud.manuelalvarez.Mis-Mangas", category: "covers")

    init(files: CoverCacheFiles, downloader: ImageDownloader = ImageDownloader()) {
        self.files = files
        self.downloader = downloader
    }

    /// Leaves in the folder exactly the covers of `items`: deletes the rest, then downloads the
    /// missing ones one after the other, in the order of `items`. A cover that fails (network, a
    /// missing image, bytes that are not an image) is logged and skipped; the others still go on.
    /// Meant for a single caller that awaits each update before the next one: two updates at once
    /// could interleave their deletions and downloads.
    func update(to items: [ReadingItem]) async {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: files.baseURL, withIntermediateDirectories: true)
        } catch {
            logger.error("Covers folder not available: \(error.localizedDescription)")
            return
        }
        removeCovers(except: Set(items.map(\.mangaID)))
        for item in items where files.existingFileURL(for: item.mangaID) == nil {
            await store(item)
        }
    }

    private func removeCovers(except kept: Set<Int>) {
        let fileManager = FileManager.default
        let keptNames = Set(kept.map { files.fileURL(for: $0).lastPathComponent })
        let stored = (try? fileManager.contentsOfDirectory(at: files.baseURL, includingPropertiesForKeys: nil)) ?? []
        for file in stored where !keptNames.contains(file.lastPathComponent) {
            do {
                try fileManager.removeItem(at: file)
            } catch {
                logger.error("Cover \(file.lastPathComponent) not removed: \(error.localizedDescription)")
            }
        }
    }

    private func store(_ item: ReadingItem) async {
        guard let address = item.coverURL, let url = URL(string: address) else {
            return
        }
        let data: Data
        do {
            data = try await downloader.data(from: url)
        } catch {
            logger.error("Cover of manga \(item.mangaID, privacy: .private) not downloaded: \(String(describing: error))")
            return
        }
        guard let jpeg = Self.thumbnail(of: data) else {
            logger.error("Cover of manga \(item.mangaID, privacy: .private) is not a readable image")
            return
        }
        do {
            // Atomic: the widget never finds half a file.
            try jpeg.write(to: files.fileURL(for: item.mangaID), options: .atomic)
        } catch {
            logger.error("Cover of manga \(item.mangaID, privacy: .private) not written: \(error.localizedDescription)")
        }
    }

    /// `data` reduced so that its longest side is at most `maxPixelSize`, as a JPEG of quality
    /// 0.8; `nil` when `data` is not an image.
    private static func thumbnail(of data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}
