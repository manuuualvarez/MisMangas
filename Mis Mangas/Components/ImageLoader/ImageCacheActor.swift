//
//  ImageCacheActor.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import UIKit

/// In-memory cover cache. Coalesces concurrent requests for the same URL into a single download
/// and answers `nil` on any failure, so callers fall back to a placeholder without crashing.
actor ImageCacheActor {
    static let shared = ImageCacheActor(downloader: ImageDownloader())

    private let downloader: ImageDownloader
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(downloader: ImageDownloader) {
        self.downloader = downloader
        cache.totalCostLimit = 50 * 1024 * 1024
        cache.countLimit = 200
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if let task = inFlight[url] {
            return await task.value
        }
        let task = Task { await download(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
        }
        return image
    }

    private func download(_ url: URL) async -> UIImage? {
        do {
            let data = try await downloader.data(from: url)
            guard let image = UIImage(data: data) else {
                return nil
            }
            return await image.byPreparingForDisplay() ?? image
        } catch {
            return nil
        }
    }

    /// Approximate decoded size in bytes (RGBA).
    private static func cost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        return Int(pixels) * 4
    }
}
