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

    @State private var phase: Phase = .loading

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
        phase = .loading
        let image = await ImageCacheActor.shared.image(for: url)
        // `.task(id:)` cancelled us because `url` changed: the new load owns `phase` now.
        guard !Task.isCancelled else {
            return
        }
        phase = image.map(Phase.success) ?? .failure
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
