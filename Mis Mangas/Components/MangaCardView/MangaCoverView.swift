//
//  MangaCoverView.swift
//  Mis Mangas
//
//  Created by Manuel Alvarez on 14/09/2026.
//

import SwiftData
import SwiftUI

/// A manga cover at a fixed size or filling its container, always 2:3 with rounded corners,
/// optionally with the score in a capsule over the top-trailing corner.
struct MangaCoverView: View {
    enum Size {
        /// For dense rows such as search suggestions.
        case thumbnail
        case small
        case medium
        case large
        /// As wide as the container allows; the height follows the 2:3 ratio.
        case fill

        var width: CGFloat? {
            switch self {
            case .thumbnail: 44
            case .small: 80
            case .medium: 140
            case .large: 200
            case .fill: nil
            }
        }

        var height: CGFloat? {
            width.map { $0 * 1.5 }
        }
    }

    let manga: Manga
    var size: Size = .small
    var showsScore = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // The clear shape reserves the 2:3 area whatever the image state (spinner, placeholder,
        // loaded), so cells never collapse while a cover loads.
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .overlay {
                RemoteImageView(url: manga.coverURL, label: String(localized: "Cover of \(manga.title)"))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if showsScore {
                    Text(manga.formattedScore)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.mmLabel)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        // Spelled with the type on purpose: written as an implicit member, the
                        // app crashed at launch while the grid measured its cells.
                        .background(Color.mmSurface.opacity(reduceTransparency ? 1 : 0.9), in: Capsule())
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
    }
}

#Preview("Medium", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaCoverView(manga: manga, size: .medium) }
}

#Preview("Fill with score", traits: .sampleData) {
    @Previewable @Query var mangas: [Manga]
    if let manga = mangas.first { MangaCoverView(manga: manga, size: .fill, showsScore: true).frame(width: 120) }
}
