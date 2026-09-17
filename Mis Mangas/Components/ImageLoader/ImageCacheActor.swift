//
//  ImageCacheActor.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import UIKit

/// In-memory cover cache. Coalesces concurrent requests for the same URL into a single download
/// and answers `nil` on any failure, so callers fall back to a placeholder without crashing.
/// Cancellation follows the callers: when the last one waiting for a URL is cancelled, the
/// shared download is cancelled too, so a cell scrolled out of view stops costing network.
actor ImageCacheActor {
    static let shared = ImageCacheActor(downloader: ImageDownloader())

    private let downloader: ImageDownloader
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    /// Who is still waiting for each in-flight download, by an opaque token per call.
    private var waiters: [URL: Set<UUID>] = [:]

    init(downloader: ImageDownloader) {
        self.downloader = downloader
        cache.totalCostLimit = 50 * 1024 * 1024
        cache.countLimit = 200
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        // Already cancelled: do not start, or join, work nobody will use.
        guard !Task.isCancelled else {
            return nil
        }
        let task = inFlight[url] ?? startDownload(url)
        let token = UUID()
        waiters[url, default: []].insert(token)
        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            // Runs outside the actor, possibly while the download is still going: hop back in.
            Task { await self.leave(url, token: token) }
        }
        leave(url, token: token)
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
        }
        return image
    }

    private func startDownload(_ url: URL) -> Task<UIImage?, Never> {
        let task = Task { await download(url) }
        inFlight[url] = task
        return task
    }

    /// Drops one waiter. Idempotent: a cancelled caller passes here twice (from the cancellation
    /// handler and on its way out). The last waiter to go takes the download with it.
    private func leave(_ url: URL, token: UUID) {
        guard var remaining = waiters[url], remaining.remove(token) != nil else {
            return
        }
        if remaining.isEmpty {
            waiters[url] = nil
            inFlight[url]?.cancel()
            inFlight[url] = nil
        } else {
            waiters[url] = remaining
        }
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
