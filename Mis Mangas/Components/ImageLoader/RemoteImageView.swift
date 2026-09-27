//
//  RemoteImageView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftUI

/// Cover image loaded through the shared `ImageCacheActor`. Shows a progress
/// indicator while loading and an accessible placeholder when there is no URL or the download
/// fails, so a cover slot is never blank. The loaded image is read as `label`, which names what
/// it shows ("Cover of Monster") rather than the fact that it is an image.
struct RemoteImageView: View {
    let url: URL?
    let label: String
    /// Whether a load cut short by a cancellation runs once more while its URL is still wanted.
    /// A screen pushed as the detail of a split view can get its disappearance right after its
    /// appearance while it stays on screen: its task is cancelled, and nothing starts it again. The
    /// detail's cover asks for this; a cell keeps the default, so a cell scrolled out of view still
    /// stops costing network.
    var retriesWhenCutShort = false

    @State private var phase: Phase = .loading
    /// The URL of the latest load: an older load that ends after it leaves `phase` alone.
    @State private var requestedURL: URL?
    /// How many times the load ran again after being cut short: once at most.
    @State private var retries = 0

    private enum Phase {
        case loading
        case success(UIImage)
        case failure
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .accessibilityLabel("Loading cover")
            case .success(let image):
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // A filling image is larger than the container. With a minimum and a maximum
                    // the frame takes the size proposed for it; with a maximum alone it would grow
                    // to the image, and a wide cover would take the taps of its neighbours.
                    // Clipping only hides the overflow; the hit area follows the frame.
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .contentShape(.rect)
                    .accessibilityLabel(label)
            case .failure:
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No cover available")
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            phase = .failure
            return
        }
        if requestedURL != url {
            retries = 0
        }
        requestedURL = url
        phase = .loading
        let image = await ImageCacheActor.shared.image(for: url)
        // A newer load, for another URL, owns `phase` now.
        guard requestedURL == url else {
            return
        }
        if !Task.isCancelled {
            phase = image.map(Phase.success) ?? .failure
            return
        }
        // Cancelled while this URL is still the one wanted: the view left the screen, or only
        // seemed to. An image that arrived anyway is shown; on a view that really left, this
        // changes nothing.
        if let image {
            phase = .success(image)
        } else if retriesWhenCutShort, retries == 0 {
            // A task of its own: the cancelled one would not be served again.
            retries += 1
            Task {
                await load()
            }
        }
    }
}

#Preview("Cover", traits: .sampleData) {
    RemoteImageView(url: URL(string: "https://cdn.myanimelist.net/images/manga/3/258224l.jpg"), label: "Cover of Monster")
        .frame(width: 140, height: 210)
}

#Preview("Placeholder", traits: .sampleData) {
    RemoteImageView(url: nil, label: "Cover of Monster")
        .frame(width: 140, height: 210)
}
